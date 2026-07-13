import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:digl/Provider/underReviewScreen.dart';
import 'package:digl/features/admin/models/admin_models.dart';
import 'package:digl/features/admin/presentation/pages/admin_dashboard_screen.dart';
import 'package:digl/features/auth/presentation/pages/login_screen.dart';
import 'package:digl/features/home/presentation/pages/home_screen.dart';
import 'package:digl/features/medical_profile/presentation/pages/health_questions_screen.dart';
import 'package:digl/features/medical_profile/services/medical_profile_service.dart';
import 'package:digl/services/zego_call_service.dart';
import 'package:digl/services/zego_incoming_call_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';

Future<void> initZegoIfNeeded({
  required String userID,
  required String userName,
}) async {
  if (ZegoCallService.isInitialized) return;

  final isConnected = await ConnectivityService.isConnected();
  if (!isConnected) return;

  final initialized = await ZegoCallService.initialize(
    userID: userID,
    userName: userName,
  );

  if (initialized) {
    try {
      await ZegoIncomingCallHandler.initialize();
    } catch (e) {
      debugPrint('⚠️ تحذير: فشل تهيئة معالج المكالمات: $e');
    }
    await Future.delayed(const Duration(seconds: 1));
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isConnected = true;
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _checkInitialConnection();
    _setupConnectivityListener();
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  Future<void> _checkInitialConnection() async {
    final connected = await ConnectivityService.isConnected();
    if (mounted) setState(() => _isConnected = connected);
  }

  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (ConnectivityResult result) {
        final connected = result != ConnectivityResult.none;
        if (!mounted) return;
        setState(() => _isConnected = connected);
        if (!connected) {
          ConnectivityService.showNoInternetSnackBar(context);
        } else {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.wifi, color: Colors.white),
                  SizedBox(width: 8),
                  Text('تم استعادة الاتصال بالإنترنت'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isConnected) return _buildNoInternetScreen();
    return _buildAuthContent();
  }

  Widget _buildNoInternetScreen() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 24),
              const Text('غير متصل بالإنترنت', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              const Text('يجب أن يكون جهازك متصلاً بالإنترنت لاستخدام التطبيق.\nيرجى التحقق من اتصال Wi-Fi أو بيانات الجوال.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 32),
              ElevatedButton.icon(onPressed: _checkInitialConnection, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthContent() {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _buildErrorScreen('حدث خطأ ما. حاول مرة أخرى.');
        if (snapshot.connectionState == ConnectionState.waiting) return _buildLoadingScreen();

        final user = snapshot.data;
        if (user == null) return const LoginScreen();

        return FutureBuilder<_ResolvedAccount>(
          future: _resolveAccount(user),
          builder: (context, accountSnapshot) {
            if (accountSnapshot.connectionState == ConnectionState.waiting) return _buildLoadingScreen();
            if (accountSnapshot.hasError || !accountSnapshot.hasData) return const LoginScreen();

            final account = accountSnapshot.data!;
            if (account.isAdmin) return AdminDashboardScreen(admin: account.adminUser!);

            final refreshedUser = FirebaseAuth.instance.currentUser ?? user;
            if (!account.emailVerificationCompleted && !refreshedUser.emailVerified) {
              return _buildEmailNotVerifiedScreen(refreshedUser);
            }

            if (!account.emailVerificationCompleted && refreshedUser.emailVerified) {
              return FutureBuilder<void>(
                future: _markEmailVerificationCompleted(refreshedUser.uid),
                builder: (context, markSnapshot) {
                  if (markSnapshot.connectionState == ConnectionState.waiting) return _buildLoadingScreen();
                  return _buildUserHome(refreshedUser, account.userData!);
                },
              );
            }

            return _buildUserHome(refreshedUser, account.userData!);
          },
        );
      },
    );
  }

  Future<_ResolvedAccount> _resolveAccount(User user) async {
    final adminDoc = await FirebaseFirestore.instance.collection('admins').doc(user.uid).get();
    if (adminDoc.exists && (adminDoc.data()?['isActive'] ?? true) == true) {
      return _ResolvedAccount.admin(AdminUser.fromFirestore(adminDoc));
    }

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (!userDoc.exists) throw Exception('user-not-found');

    final userData = userDoc.data() as Map<String, dynamic>;
    final emailVerificationCompleted = userData['emailVerificationCompleted'] == true;
    if (!emailVerificationCompleted) {
      await user.reload();
    }
    return _ResolvedAccount.user(
      userData,
      emailVerificationCompleted: emailVerificationCompleted,
    );
  }

  Future<void> _markEmailVerificationCompleted(String uid) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'emailVerificationCompleted': true,
      'emailVerifiedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Widget _buildUserHome(User user, Map<String, dynamic> userData) {
    final accountType = userData['accountType'] ?? 'patient';
    final userName = userData['fullName'] ?? 'User_${user.uid.substring(0, 5)}';

    if (_isConnected) initZegoIfNeeded(userID: user.uid, userName: userName);

    if (accountType == 'doctor') {
      final isVerified = userData['isVerified'] == true;
      final hasLicense = userData['hasLicenseDocuments'] == true;
      if (!isVerified || !hasLicense) return const UnderReviewScreen();
      return const HomeScreen();
    }

    if (accountType == 'patient') {
      return FutureBuilder<bool>(
        future: MedicalProfileService.hasHealthProfile(),
        builder: (context, profileSnapshot) {
          if (profileSnapshot.connectionState == ConnectionState.waiting) return _buildLoadingScreen();
          if (profileSnapshot.hasError) return _buildErrorScreen('حدث خطأ أثناء التحقق من الملف الصحي.');
          final hasProfile = profileSnapshot.data ?? false;
          if (!hasProfile) return const HealthQuestionsScreen();
          return const HomeScreen();
        },
      );
    }

    return const HomeScreen();
  }

  Widget _buildEmailNotVerifiedScreen(User user) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mark_email_unread_rounded, size: 76, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 20),
              const Text('يرجى تفعيل البريد الإلكتروني أولاً', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('أرسلنا رابط التفعيل إلى ${user.email ?? 'بريدك الإلكتروني'}. افتح الرابط ثم اضغط على تحقق مرة أخرى.', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  await user.reload();
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.verified_rounded),
                label: const Text('تحقق مرة أخرى'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await user.sendEmailVerification();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إعادة إرسال رابط التفعيل')));
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة إرسال رابط التفعيل'),
              ),
              TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('تسجيل الخروج')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [CircularProgressIndicator(), SizedBox(height: 16), Text('جاري التحميل...')],
        ),
      ),
    );
  }

  Widget _buildErrorScreen(String message) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const AuthGate())),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResolvedAccount {
  final bool isAdmin;
  final AdminUser? adminUser;
  final Map<String, dynamic>? userData;
  final bool emailVerificationCompleted;

  const _ResolvedAccount._({
    required this.isAdmin,
    this.adminUser,
    this.userData,
    this.emailVerificationCompleted = false,
  });

  factory _ResolvedAccount.admin(AdminUser adminUser) => _ResolvedAccount._(
        isAdmin: true,
        adminUser: adminUser,
        emailVerificationCompleted: true,
      );

  factory _ResolvedAccount.user(Map<String, dynamic> userData, {required bool emailVerificationCompleted}) => _ResolvedAccount._(
        isAdmin: false,
        userData: userData,
        emailVerificationCompleted: emailVerificationCompleted,
      );
}
