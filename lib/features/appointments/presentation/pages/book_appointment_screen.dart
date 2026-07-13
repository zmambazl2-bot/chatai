import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/doctor_image_utils.dart';
import '../../../../core/widgets/premium_ui.dart';
import '../../../home/presentation/pages/home_screen.dart';
import '../../../maps/widgets/doctor_location_map_card.dart';

class BookAppointmentScreen extends StatefulWidget {
  final String? initialDoctorName;
  final String? initialSpecialtyName;

  const BookAppointmentScreen({
    super.key,
    this.initialDoctorName,
    this.initialSpecialtyName,
  });

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? _selectedSpecialty;
  String? _selectedDoctor;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String? _selectedLocation;
  String? _selectedPayment;
  String? _selectedWorkplace;

  String? _doctorImageUrl;
  String? _patientImageUrl;

  bool _isLoading = false;
  List<Map<String, dynamic>> _doctors = [];
  List<Map<String, dynamic>> _workplaces = [];
  Map<String, List<String>> _availableTimes = {};
  Map<String, List<String>> _bookedTimes = {};
  final Map<String, Map<String, _DayAvailabilityStatus>> _availabilityCache = {};

  final List<String> specialties = [
    'القلب',
    'الأسنان',
    'العيون',
    'الباطنة',
    'الجلدية',
    'العظام',
  ];

  @override
  void initState() {
    super.initState();
    _loadDoctors();
  }

  Future<void> _loadDoctors() async {
    final snapshot = await _firestore
        .collection('users')
        .where('accountType', isEqualTo: 'doctor')
        .where('isVerified', isEqualTo: true)
        .get();

    final loadedDoctors = snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
    Map<String, dynamic>? initialDoctor;
    if (widget.initialDoctorName != null) {
      for (final doctor in loadedDoctors) {
        if (doctor['fullName']?.toString() == widget.initialDoctorName) {
          initialDoctor = doctor;
          break;
        }
      }
    }

    setState(() {
      _doctors = loadedDoctors;
      if (initialDoctor != null) {
        _selectedDoctor = initialDoctor['fullName']?.toString();
        _selectedSpecialty = widget.initialSpecialtyName ?? initialDoctor['specialtyName']?.toString();
        _doctorImageUrl = initialDoctor['profileImageUrl']?.toString() ?? initialDoctor['photoURL']?.toString();
      }
    });

    final doctorId = initialDoctor?['uid']?.toString();
    if (doctorId != null && doctorId.isNotEmpty) {
      await _loadDoctorWorkplaces(doctorId);
    }
  }

  Future<void> _loadDoctorWorkplaces(String doctorId) async {
    final doc = await _firestore.collection('users').doc(doctorId).get();
    if (doc.exists) {
      final data = doc.data()!;
      final workplaces = List<Map<String, dynamic>>.from(data['workplaces'] ?? []);

      setState(() {
        _workplaces = workplaces;
        _selectedWorkplace = null;
        _selectedLocation = null;
        _availableTimes = {};
        _bookedTimes = {};
        _availabilityCache.clear();
      });
    }
  }

  Future<void> _loadAvailableTimes(String workplaceName, DateTime date) async {
    final dayName = DateFormat('EEEE', 'ar').format(date);
    final doctor = _doctors.firstWhere((d) => d['fullName'] == _selectedDoctor);
    final workplaces = List<Map<String, dynamic>>.from(doctor['workplaces'] ?? []);

    final workplace = workplaces.firstWhere(
          (wp) => wp['name'] == workplaceName,
      orElse: () => {},
    );

    if (workplace.isNotEmpty) {
      final workDays = Map<String, dynamic>.from(workplace['workDays'] ?? {});
      final dayTimes = List<Map<String, dynamic>>.from(workDays[dayName] ?? []);

      await _loadBookedTimes(doctor['uid'], workplaceName, date);

      final availableTimes = <String>[];
      for (var timeSlot in dayTimes) {
        final startTime = TimeOfDay(
          hour: timeSlot['startHour'],
          minute: timeSlot['startMinute'],
        );
        final endTime = TimeOfDay(
          hour: timeSlot['endHour'],
          minute: timeSlot['endMinute'],
        );

        print('⏰ فترة العمل الأصلية: ${startTime.format(context)} - ${endTime.format(context)}');
        print('🔢 البيانات الخام: startHour=${timeSlot['startHour']}, endHour=${timeSlot['endHour']}');

        var currentHour = startTime.hour;
        var currentMinute = startTime.minute;

        while (currentHour < endTime.hour ||
            (currentHour == endTime.hour && currentMinute < endTime.minute)) {

          final timeStr = '${currentHour.toString().padLeft(2, '0')}:${currentMinute.toString().padLeft(2, '0')}';

          // التحقق إذا كان الوقت محجوزاً مسبقاً
          final isBooked = _isTimeBooked(workplaceName, timeStr);
          if (!isBooked) {
            availableTimes.add(timeStr);
            print('✅ الوقت المتاح: $timeStr');
          }

          // إضافة ساعة كاملة فقط
          currentHour += 1;
          currentMinute = 0;
        }
      }

      print('📋 إجمالي الأوقات المتاحة: ${availableTimes.length}');
      print('📋 الأوقات المتاحة النهائية: $availableTimes');

      setState(() {
        _availableTimes[workplaceName] = availableTimes;
      });
    }
  }


  Future<DateTime?> _showAvailabilityDatePicker() async {
    if (_selectedDoctor == null || _selectedWorkplace == null) return null;
    final doctor = _doctors.firstWhere((d) => d['fullName'] == _selectedDoctor, orElse: () => {});
    final doctorId = doctor['uid']?.toString() ?? '';
    if (doctorId.isEmpty) return null;

    final today = DateTime.now();
    DateTime visibleMonth = DateTime(today.year, today.month);
    Map<String, _DayAvailabilityStatus> visibleStatuses = _availabilityCache[_availabilityMonthKey(visibleMonth)] ?? {};
    bool isLoadingMonth = visibleStatuses.isEmpty;
    final requestedMonthKeys = <String>{};

    Future<void> loadMonth(StateSetter setDialogState, DateTime month) async {
      final monthKey = _availabilityMonthKey(month);
      final cached = _availabilityCache[monthKey];
      if (cached != null) {
        setDialogState(() {
          visibleStatuses = cached;
          isLoadingMonth = false;
        });
        return;
      }

      if (!requestedMonthKeys.add(monthKey)) return;
      setDialogState(() => isLoadingMonth = true);
      try {
        final loaded = await _loadMonthAvailabilityFast(doctorId, _selectedWorkplace!, month);
        if (!mounted) return;
        _availabilityCache[monthKey] = loaded;
        setDialogState(() {
          visibleStatuses = loaded;
          isLoadingMonth = false;
        });
      } catch (_) {
        if (!mounted) return;
        setDialogState(() => isLoadingMonth = false);
      } finally {
        requestedMonthKeys.remove(monthKey);
      }
    }

    return showDialog<DateTime>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (isLoadingMonth && visibleStatuses.isEmpty) {
              Future.microtask(() => loadMonth(setDialogState, visibleMonth));
            }

            final theme = Theme.of(context);
            final colorScheme = theme.colorScheme;
            final monthDays = _calendarDaysForMonth(visibleMonth);

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'الشهر السابق',
                            onPressed: () {
                              final previous = DateTime(visibleMonth.year, visibleMonth.month - 1);
                              setDialogState(() {
                                visibleMonth = previous;
                                visibleStatuses = _availabilityCache[_availabilityMonthKey(previous)] ?? {};
                                isLoadingMonth = visibleStatuses.isEmpty;
                              });
                              loadMonth(setDialogState, previous);
                            },
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  DateFormat('MMMM yyyy', 'ar').format(visibleMonth),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                if (isLoadingMonth)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: const LinearProgressIndicator(minHeight: 3),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'الشهر التالي',
                            onPressed: () {
                              final next = DateTime(visibleMonth.year, visibleMonth.month + 1);
                              setDialogState(() {
                                visibleMonth = next;
                                visibleStatuses = _availabilityCache[_availabilityMonthKey(next)] ?? {};
                                isLoadingMonth = visibleStatuses.isEmpty;
                              });
                              loadMonth(setDialogState, next);
                            },
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: ['س', 'ح', 'ن', 'ث', 'ر', 'خ', 'ج'].map((day) {
                          return Expanded(
                            child: Center(
                              child: Text(
                                day,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final cellSpacing = constraints.maxWidth < 360 ? 4.0 : 6.0;
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: monthDays.length,
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              crossAxisSpacing: cellSpacing,
                              mainAxisSpacing: cellSpacing,
                              childAspectRatio: .86,
                            ),
                            itemBuilder: (context, index) {
                              final day = monthDays[index];
                              final inVisibleMonth = day.month == visibleMonth.month;
                              final isPast = day.isBefore(DateTime(today.year, today.month, today.day));
                              final status = visibleStatuses[_appointmentDateKey(day)];
                              final disabled = isPast || !inVisibleMonth || status == null || status == _DayAvailabilityStatus.full || status == _DayAvailabilityStatus.offDay;
                              final color = status == null
                                  ? colorScheme.outline
                                  : _availabilityColor(status, theme);
                              return InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: disabled ? null : () => Navigator.pop(dialogContext, day),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(disabled ? .10 : .22),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: color.withOpacity(inVisibleMonth ? .9 : .25)),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        DateFormat('d', 'ar').format(day),
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: inVisibleMonth ? colorScheme.onSurface : colorScheme.outline,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      _availabilityLegend(theme),
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('إلغاء'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _availabilityMonthKey(DateTime month) => DateFormat('yyyyMM').format(month);

  List<DateTime> _calendarDaysForMonth(DateTime month) {
    final firstDay = DateTime(month.year, month.month);
    final leadingDays = firstDay.weekday % 7;
    final gridStart = firstDay.subtract(Duration(days: leadingDays));
    return List.generate(42, (index) => DateTime(gridStart.year, gridStart.month, gridStart.day + index));
  }

  Widget _availabilityLegend(ThemeData theme) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: const [
        _LegendDot(color: Colors.green, label: 'متاح بالكامل'),
        _LegendDot(color: Colors.amber, label: 'متاح جزئياً'),
        _LegendDot(color: Colors.red, label: 'ممتلئ'),
        _LegendDot(color: Colors.blue, label: 'لا يوجد دوام'),
      ],
    );
  }

  Color _availabilityColor(_DayAvailabilityStatus status, ThemeData theme) {
    switch (status) {
      case _DayAvailabilityStatus.free:
        return Colors.green;
      case _DayAvailabilityStatus.partial:
        return Colors.amber;
      case _DayAvailabilityStatus.full:
        return Colors.red;
      case _DayAvailabilityStatus.offDay:
        return Colors.blue;
    }
  }


  int _countWorkdaySlots(String workplaceName, DateTime date) {
    final dayName = DateFormat('EEEE', 'ar').format(date);
    final doctor = _doctors.firstWhere(
      (d) => d['fullName'] == _selectedDoctor,
      orElse: () => {},
    );
    if (doctor.isEmpty) return 0;

    final workplaces = List<Map<String, dynamic>>.from(doctor['workplaces'] ?? []);
    final workplace = workplaces.firstWhere(
      (wp) => wp['name'] == workplaceName,
      orElse: () => {},
    );
    if (workplace.isEmpty) return 0;

    final workDays = Map<String, dynamic>.from(workplace['workDays'] ?? {});
    final dayTimes = List<Map<String, dynamic>>.from(workDays[dayName] ?? []);
    var totalSlots = 0;

    for (final timeSlot in dayTimes) {
      var currentHour = (timeSlot['startHour'] as num?)?.toInt() ?? 0;
      final endHour = (timeSlot['endHour'] as num?)?.toInt() ?? currentHour;
      while (currentHour < endHour) {
        totalSlots++;
        currentHour++;
      }
    }

    return totalSlots;
  }

  Future<Map<String, _DayAvailabilityStatus>> _loadMonthAvailabilityFast(String doctorId, String workplaceName, DateTime month) async {
    final firstMonthDay = DateTime(month.year, month.month);
    final visibleDays = _calendarDaysForMonth(firstMonthDay);
    final firstVisibleDay = visibleDays.first;
    final lastVisibleDay = DateTime(visibleDays.last.year, visibleDays.last.month, visibleDays.last.day, 23, 59, 59);

    final bookedByDate = <String, Set<String>>{};
    final appointmentsQuery = _firestore
        .collection('appointments')
        .where('doctorId', isEqualTo: doctorId)
        .where('workplace', isEqualTo: workplaceName)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(firstVisibleDay))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(lastVisibleDay))
        .get();
    final slotsQuery = _firestore
        .collection('appointment_slots')
        .where('doctorId', isEqualTo: doctorId)
        .where('workplace', isEqualTo: workplaceName)
        .where('dateKey', isGreaterThanOrEqualTo: _appointmentDateKey(firstVisibleDay))
        .where('dateKey', isLessThanOrEqualTo: _appointmentDateKey(lastVisibleDay))
        .get();

    final responses = await Future.wait([appointmentsQuery, slotsQuery]);
    final appointmentsSnapshot = responses[0];
    final slotsSnapshot = responses[1];

    for (final doc in appointmentsSnapshot.docs) {
      final data = doc.data();
      final status = data['status'] as String?;
      final time = data['time'] as String?;
      final date = data['date'] as Timestamp?;
      if (date != null &&
          time != null &&
          (status == 'pending' || status == 'confirmed')) {
        bookedByDate.putIfAbsent(_appointmentDateKey(date.toDate()), () => <String>{}).add(time);
      }
    }

    for (final slotDoc in slotsSnapshot.docs) {
      final data = slotDoc.data();
      final dateKey = data['dateKey']?.toString();
      final time = data['time']?.toString();
      if (dateKey != null && time != null) {
        bookedByDate.putIfAbsent(dateKey, () => <String>{}).add(time);
      }
    }

    final result = <String, _DayAvailabilityStatus>{};
    for (final day in visibleDays) {
      final dateKey = _appointmentDateKey(day);
      final totalSlots = _countWorkdaySlots(workplaceName, day);
      if (totalSlots == 0) {
        result[dateKey] = _DayAvailabilityStatus.offDay;
        continue;
      }
      final bookedCount = bookedByDate[dateKey]?.length ?? 0;
      if (bookedCount >= totalSlots) {
        result[dateKey] = _DayAvailabilityStatus.full;
      } else if (bookedCount > 0) {
        result[dateKey] = _DayAvailabilityStatus.partial;
      } else {
        result[dateKey] = _DayAvailabilityStatus.free;
      }
    }
    return result;
  }

  String _appointmentDateKey(DateTime date) => DateFormat('yyyyMMdd').format(date);

  String _appointmentSlotId({
    required String doctorId,
    required String workplaceName,
    required DateTime date,
    required String time,
  }) {
    final safeWorkplace = workplaceName.replaceAll(RegExp(r'[\/#?%*:|"<>]'), '_');
    return '${doctorId}_${safeWorkplace}_${_appointmentDateKey(date)}_$time';
  }

  Future<void> _loadBookedTimes(String doctorId, String workplaceName, DateTime date) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

      // جلب جميع المواعيد للطبيب وفلترتها محلياً
      final snapshot = await _firestore
          .collection('appointments')
          .where('doctorId', isEqualTo: doctorId)
          .get();

      final bookedTimes = <String>[];
      for (var doc in snapshot.docs) {
        final data = doc.data();

        // فلترة محلياً
        final appointmentWorkplace = data['workplace'] as String?;
        final appointmentDate = data['date'] as Timestamp?;
        final appointmentStatus = data['status'] as String?;
        final appointmentTime = data['time'] as String?;

        if (appointmentWorkplace == workplaceName &&
            appointmentDate != null &&
            !appointmentDate.toDate().isBefore(startOfDay) &&
            !appointmentDate.toDate().isAfter(endOfDay) &&
            (appointmentStatus == 'pending' || appointmentStatus == 'confirmed') &&
            appointmentTime != null) {
          bookedTimes.add(appointmentTime);
        }
      }

      final slotsSnapshot = await _firestore
          .collection('appointment_slots')
          .where('doctorId', isEqualTo: doctorId)
          .where('workplace', isEqualTo: workplaceName)
          .where('dateKey', isEqualTo: _appointmentDateKey(date))
          .get();
      for (final slotDoc in slotsSnapshot.docs) {
        final slotTime = slotDoc.data()['time']?.toString();
        if (slotTime != null && slotTime.isNotEmpty && !bookedTimes.contains(slotTime)) {
          bookedTimes.add(slotTime);
        }
      }

      setState(() {
        _bookedTimes[workplaceName] = bookedTimes;
      });
    } catch (e, s) {
      print("Error loading booked times: $e");
      print(s);
    }
  }

  bool _isTimeBooked(String workplaceName, String timeStr) {
    return _bookedTimes[workplaceName]?.contains(timeStr) ?? false;
  }

  void _confirmBooking() async {
    if (_auth.currentUser == null ||
        _selectedDoctor == null ||
        _selectedDate == null ||
        _selectedTime == null ||
        _selectedWorkplace == null ||
        _selectedPayment == null) return;

    // التحقق مرة أخرى إذا كان الوقت محجوزاً
    final timeStr = '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}';
    if (_isTimeBooked(_selectedWorkplace!, timeStr)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ هذا الموعد محجوز مسبقاً، يرجى اختيار وقت آخر')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final currentUserId = _auth.currentUser!.uid;

      String userName = 'مستخدم';
      String userImageUrl = '';
      String userPhone = '';

      final patientDoc = await _firestore.collection('users').doc(currentUserId).get();
      if (patientDoc.exists) {
        final data = patientDoc.data();
        if (data != null) {
          userName = data['fullName'] ?? 'مستخدم';
          userImageUrl = data['profilePicture'] ?? data['photoURL'] ?? '';
          userPhone = data['phone'] ?? '';
        }
      }

      final doctor = _doctors.firstWhere((d) => d['fullName'] == _selectedDoctor);
      final doctorId = doctor['uid'];
      final doctorImageUrl = doctor['profileImageUrl'] ?? '';
      final doctorPhone = doctor['phone'] ?? '';
      final bookingFee = _bookingFeeForDoctor(doctor);

      final appointmentDateTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );

      final slotId = _appointmentSlotId(
        doctorId: doctorId,
        workplaceName: _selectedWorkplace!,
        date: _selectedDate!,
        time: timeStr,
      );
      final slotRef = _firestore.collection('appointment_slots').doc(slotId);
      final appointmentRef = _firestore.collection('appointments').doc();

      await _firestore.runTransaction((transaction) async {
        final slotSnapshot = await transaction.get(slotRef);
        if (slotSnapshot.exists) {
          throw StateError('appointment_slot_already_booked');
        }

        final appointmentData = {
          'userId': currentUserId,
          'userName': userName,
          'userImageUrl': userImageUrl,
          'userPhone': userPhone,
          'doctorId': doctorId,
          'doctorName': _selectedDoctor,
          'doctorImageUrl': doctorImageUrl,
          'doctorPhone': doctorPhone,
          'specialtyName': _selectedSpecialty,
          'date': Timestamp.fromDate(_selectedDate!),
          'time': timeStr,
          'workplace': _selectedWorkplace,
          'payment': _selectedPayment,
          'paymentMethod': _selectedPayment,
          'paymentStatus': _selectedPayment == 'الدفع عند المقابلة' ? 'pending_at_visit' : 'unpaid',
          'bookingFee': bookingFee,
          'consultationFee': bookingFee,
          'price': bookingFee,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'slotId': slotId,
          'notified': {
            '1day': false,
            '6hours': false,
            '1hour': false,
            'ontime': false,
            'cancelled': false,
          }
        };

        transaction.set(slotRef, {
          'appointmentId': appointmentRef.id,
          'doctorId': doctorId,
          'userId': currentUserId,
          'workplace': _selectedWorkplace,
          'dateKey': _appointmentDateKey(_selectedDate!),
          'date': Timestamp.fromDate(_selectedDate!),
          'time': timeStr,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.set(appointmentRef, appointmentData);
      });

      _availabilityCache.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم تأكيد الحجز بنجاح!')),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen()),
      );
    } catch (e) {
      final message = e is StateError && e.message == 'appointment_slot_already_booked'
          ? '❌ هذا الموعد محجوز مسبقاً، يرجى اختيار وقت آخر'
          : '❌ حدث خطأ أثناء الحجز: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFormComplete = _selectedDoctor != null &&
        _selectedDate != null &&
        _selectedTime != null &&
        _selectedWorkplace != null &&
        _selectedPayment != null;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.primary,
        elevation: 0,
        centerTitle: true,
        title: const Text('حجز موعد جديد'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : PremiumGradientBackground(
              child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        child: Column(
          children: [
            _buildDropdownCard(
              title: 'اختر القسم والطبيب',
              children: [
                _buildDropdown<String>(
                  label: 'القسم',
                  value: _selectedSpecialty,
                  items: specialties,
                  icon: Icons.medical_services,
                  onChanged: (val) {
                    setState(() {
                      _selectedSpecialty = val;
                      _selectedDoctor = null;
                      _workplaces = [];
                      _selectedWorkplace = null;
                      _doctorImageUrl = null;
                      _availableTimes = {};
                      _bookedTimes = {};
                    });
                  },
                ),
                const SizedBox(height: 16),
                _buildDropdown<String>(
                  label: 'الطبيب',
                  value: _selectedDoctor,
                  items: _doctors
                      .where((d) =>
                  _selectedSpecialty == null ||
                      d['specialtyName'] == _selectedSpecialty)
                      .map((d) => d['fullName'] as String)
                      .toList(),
                  icon: Icons.person,
                  onChanged: (val) async {
                    setState(() {
                      _selectedDoctor = val;
                      _availableTimes = {};
                      _bookedTimes = {};
                      _availabilityCache.clear();
                      _selectedDate = null;
                      _selectedTime = null;
                    });
                    if (val != null) {
                      final doctor = _doctors.firstWhere((d) => d['fullName'] == val);
                      _doctorImageUrl = doctor['profileImageUrl'];
                      await _loadDoctorWorkplaces(doctor['uid']);
                    }
                  },
                ),
              ],
            ),

            if (_selectedDoctor != null)
              _buildDoctorDetails(
                _doctors.firstWhere((d) => d['fullName'] == _selectedDoctor),
              ),

            const SizedBox(height: 24),

            if (_selectedDoctor != null && _workplaces.isNotEmpty)
              _buildDropdownCard(
                title: 'اختر مستشفى او عيادة',
                children: [
                  _buildDropdown<String>(
                    label: 'مستشفى او عيادة',
                    value: _selectedWorkplace,
                    items: _workplaces.map((wp) => wp['name'] as String).toList(),
                    icon: Icons.work,
                    onChanged: (val) {
                      setState(() {
                        _selectedWorkplace = val;
                        _selectedDate = null;
                        _selectedTime = null;
                        _availableTimes = {};
                        _bookedTimes = {};
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_selectedWorkplace != null)
                    _buildWorkplaceSchedule(_selectedWorkplace!),
                ],
              ),

            const SizedBox(height: 24),

            if (_selectedWorkplace != null)
              _buildDropdownCard(
                title: 'حدد تاريخ و وقت الحجز',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today),
                          label: Text(_selectedDate == null
                              ? 'اختر التاريخ'
                              : DateFormat('yyyy/MM/dd').format(_selectedDate!)),
                          onPressed: () async {
                            final picked = await _showAvailabilityDatePicker();
                            if (picked != null) {
                              setState(() {
                                _selectedDate = picked;
                                _selectedTime = null;
                              });
                              if (_selectedWorkplace != null) {
                                await _loadAvailableTimes(_selectedWorkplace!, picked);
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTimeDropdown(),
                      ),
                    ],
                  ),
                  if (_selectedDate != null && _availableTimes[_selectedWorkplace]?.isEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'لا توجد أوقات متاحة في هذا التاريخ',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                ],
              ),

            const SizedBox(height: 24),

            _buildDropdownCard(
              title: 'اختر طريقة الدفع',
              children: [
                _buildDropdown<String>(
                  label: 'طريقة الدفع',
                  value: _selectedPayment,
                  items: const ['الدفع عند المقابلة', 'بطاقة بنكية'],
                  icon: Icons.payment,
                  onChanged: (val) => setState(() => _selectedPayment = val),
                ),
              ],
            ),

            const SizedBox(height: 32),

            PremiumSurface(
              padding: const EdgeInsets.all(8),
              radius: 24,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline),
                label: Text(_selectedPayment == 'الدفع عند المقابلة' ? 'تأكيد الحجز' : 'تأكيد الحجز والدفع'),
                onPressed: isFormComplete ? _confirmBooking : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
              ),
            ),
            ),
          ],
        ),
      ),
            ),
    );
  }

  Widget _buildTimeDropdown() {
    final times = _selectedWorkplace != null && _selectedDate != null
        ? _availableTimes[_selectedWorkplace] ?? []
        : [];

    return DropdownButtonFormField<TimeOfDay>(
      value: _selectedTime,
      decoration: InputDecoration(
        labelText: 'الوقت',
        prefixIcon: Icon(Icons.access_time, color: Theme.of(context).colorScheme.primary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        enabled: times.isNotEmpty,
      ),
      items: times.map((timeStr) {
        final parts = timeStr.split(':');
        final time = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        return DropdownMenuItem<TimeOfDay>(
          value: time,
          child: Text(time.format(context), style: TextStyle(fontSize: 13),),
        );
      }).toList(),
      onChanged: (time) => setState(() => _selectedTime = time),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required IconData icon,
    required void Function(T?) onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      ),
      items: items
          .map((item) => DropdownMenuItem<T>(value: item, child: Text(item.toString())))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildDropdownCard({required String title, required List<Widget> children}) {
    return PremiumSurface(
      margin: const EdgeInsets.only(bottom: 16),
      radius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PremiumSectionHeader(
            title: title,
            subtitle: 'خطوة مصممة لتسهيل الحجز بسرعة ووضوح',
            icon: Icons.auto_awesome_rounded,
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDoctorDetails(Map<String, dynamic> doctor) {
    final theme = Theme.of(context);
    final bookingFee = _bookingFeeForDoctor(doctor);
    return PremiumSurface(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(16),
      radius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundImage: DoctorImageUtils.imageProvider(imageUrl: (doctor['profileImageUrl'] ?? doctor['photoURL'])?.toString(), gender: doctor['gender'] ?? doctor['sex']),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doctor['fullName'],
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
                  Text(doctor['specialtyName'] ?? '',
                      style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(.64))),
                  const SizedBox(height: 4),
                  if (doctor['rating'] != null)
                    Row(
                      children: [
                        Icon(Icons.star, size: 16, color: theme.colorScheme.tertiary),
                        Text(doctor['rating'].toString()),
                      ],
                    ),
                  if (doctor['specialty'] != null)
                    Text(
                      doctor['specialty'],
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(.64)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: Icon(Icons.payments, size: 16, color: theme.colorScheme.primary),
                label: Text('قيمة الحجز: ${_formatFee(bookingFee)}'),
              ),
              Chip(avatar: Icon(Icons.reviews, size: 16, color: theme.colorScheme.primary), label: Text('المراجعات: ${doctor['reviewsCount'] ?? doctor['reviewCount'] ?? 0}')),
              if (doctor['moodIndicator'] != null || doctor['mood'] != null) Chip(label: Text('مؤشر الحالة: ${doctor['moodIndicator'] ?? doctor['mood']}')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'عنوان العيادة: ${doctor['address'] ?? doctor['clinicAddress'] ?? 'غير محدد'}',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          DoctorLocationMapCard(
            latitude: (doctor['latitude'] as num?)?.toDouble(),
            longitude: (doctor['longitude'] as num?)?.toDouble(),
            address: (doctor['address'] ?? doctor['clinicAddress'])?.toString(),
          ),
        ],
      ),
    );
  }

  double _bookingFeeForDoctor(Map<String, dynamic> doctor) {
    final value = doctor['bookingFee'] ??
        doctor['consultationFee'] ??
        doctor['sessionPrice'] ??
        doctor['minSessionPrice'] ??
        doctor['minPrice'] ??
        0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  String _formatFee(double fee) {
    if (fee <= 0) return 'غير محددة';
    final hasDecimals = fee.truncateToDouble() != fee;
    return '${fee.toStringAsFixed(hasDecimals ? 2 : 0)} ريال';
  }

  Widget _buildWorkplaceSchedule(String workplaceName) {
    final workplace = _workplaces.firstWhere((wp) => wp['name'] == workplaceName);
    final workDays = Map<String, dynamic>.from(workplace['workDays'] ?? {});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'أوقات الدوام:',
          style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface),
        ),
        const SizedBox(height: 8),
        ...workDays.entries.map((entry) {
          final dayName = entry.key;
          final times = List<Map<String, dynamic>>.from(entry.value ?? []);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(dayName),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    children: times.map((time) {
                      final start = TimeOfDay(
                        hour: time['startHour'],
                        minute: time['startMinute'],
                      );
                      final end = TimeOfDay(
                        hour: time['endHour'],
                        minute: time['endMinute'],
                      );
                      return Chip(
                        label: Text('${start.format(context)} - ${end.format(context)}'),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}

enum _DayAvailabilityStatus { free, partial, full, offDay }

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
