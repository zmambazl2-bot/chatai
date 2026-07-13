import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';

import '../../../../core/config/medical_theme.dart';
import '../../../../core/utils/doctor_image_utils.dart';
import '../widgets/message_reactions_widget.dart';

class GroupConsultationScreen extends StatefulWidget {
  const GroupConsultationScreen({super.key});

  @override
  State<GroupConsultationScreen> createState() => _GroupConsultationScreenState();
}

class _GroupConsultationScreenState extends State<GroupConsultationScreen> {
  static const int _maxInlineAttachmentBytes = 900 * 1024;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isSending = false;
  Map<String, dynamic>? _replyToMessage;
  Set<String> _hiddenMessageIds = <String>{};

  List<PlatformFile> _selectedFiles = [];
  bool _isRecording = false;
  String? _playingMessageId;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;
  final Map<String, String> _inlineAudioFiles = {};

  @override
  void initState() {
    super.initState();
    _loadHiddenMessages();
    _configureAudioPlayer();
  }


  void _configureAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      if (state == PlayerState.stopped || state == PlayerState.completed) {
        setState(() {
          _playingMessageId = null;
          _audioPosition = Duration.zero;
        });
      }
    });
    _audioPlayer.onDurationChanged.listen((value) {
      if (mounted) setState(() => _audioDuration = value);
    });
    _audioPlayer.onPositionChanged.listen((value) {
      if (mounted) setState(() => _audioPosition = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white.withOpacity(.18),
              child: const Icon(Icons.groups_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                "الاستشارة الجماعية",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        elevation: 2,
        actions: [
          IconButton(
            tooltip: 'حذف جميع المحادثات من جهازي',
            onPressed: _confirmHideAllMessages,
            icon: const Icon(Icons.delete_sweep_rounded),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withOpacity(.06),
              theme.scaffoldBackgroundColor,
              ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
            Expanded(child: _buildMessagesList()),
            if (_replyToMessage != null) _buildReplyPreview(),
            if (_selectedFiles.isNotEmpty) _buildSelectedFilesPreview(),
            _buildMessageInput(),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection("group_consultations").orderBy("timestamp", descending: false).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final theme = Theme.of(context);
        final isDarkMode = theme.brightness == Brightness.dark;
        final messages = snapshot.data!.docs.where((doc) => !_hiddenMessageIds.contains(doc.id)).toList();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final doc = messages[index];
            final message = doc.data() as Map<String, dynamic>;
            final isMe = message['senderId'] == _auth.currentUser?.uid;
            return GestureDetector(
              onLongPress: () => _showMessageOptions(doc.id, message, isMe),
              onDoubleTap: () => setState(() => _replyToMessage = message),
              child: _buildMessageBubble(doc.id, message, isMe, theme, isDarkMode),
            );
          },
        );
      },
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      width: double.infinity,
      color: Colors.grey[200],
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "ردًا على: ${_replyToMessage!['text'] ?? ''}",
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _replyToMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedFilesPreview() {
    return Container(
      padding: const EdgeInsets.all(8),
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedFiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final file = _selectedFiles[index];
          final ext = (file.extension ?? file.name.split('.').last).toLowerCase();
          final isImage = ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'webp';
          return Stack(
            children: [
              Container(
                width: 100,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: isImage
                    ? (file.bytes != null
                        ? Image.memory(file.bytes!, fit: BoxFit.cover)
                        : file.path != null
                            ? Image.file(File(file.path!), fit: BoxFit.cover)
                            : const Center(child: Icon(Icons.image_not_supported, size: 40)))
                    : const Center(child: Icon(Icons.insert_drive_file, size: 40)),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 20, color: Colors.red),
                  onPressed: () {
                    setState(() => _selectedFiles.removeAt(index));
                  },
                ),
              )
            ],
          );
        },
      ),
    );
  }




  Widget _buildMessageBubble(String messageId, Map<String, dynamic> message, bool isMe, ThemeData them, bool isDarkMode) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isMe
                ? MedicalTheme.primaryMedicalBlue
                : isDarkMode
                    ? const Color(0xFF1F2937)
                    : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDarkMode ? .18 : .08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundImage: DoctorImageUtils.imageProvider(imageUrl: message['senderImage']?.toString(), gender: message['senderGender']),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message['senderName'] ?? 'مستخدم',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              if (!isMe) const SizedBox(height: 4),
              if (message['replyTo'] != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isDarkMode? Colors.grey[600]: Colors.grey[300],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text("ردًا على: ${message['replyTo']['text'] ?? ''}"),
                ),
              if (_messageFiles(message).isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(_messageFiles(message).length, (index) {
                    final file = _messageFiles(message)[index];
                    final fileType = (file['fileType'] ?? '').toString();
                    final isImage = fileType == 'image' || fileType == 'image_inline';
                    final isAudio = fileType == 'audio' || fileType == 'audio_inline';
                    final fileUrl = (file['fileUrl'] ?? '').toString();
                    final fileBase64 = (file['fileBase64'] ?? '').toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: isImage
                          ? GestureDetector(
                        onTap: (fileUrl.isNotEmpty || fileBase64.isNotEmpty)
                            ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ImagePreviewScreen(imageUrl: fileUrl, imageBase64: fileBase64),
                          ),
                        )
                            : null,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: fileUrl.isNotEmpty
                              ? Image.network(
                            fileUrl,
                            height: 150,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          )
                              : Image.memory(
                            base64Decode(fileBase64),
                            height: 150,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                          : isAudio
                              ? _buildAudioMessage(
                                  messageId: '${messageId}_$index',
                                  audioUrl: fileUrl,
                                  audioBase64: fileBase64,
                                  theme: them,
                                  isMe: isMe,
                                )
                              : InkWell(
                                  onTap: () => _openGroupFile(
                                    messageId: '${messageId}_$index',
                                    fileUrl: fileUrl,
                                    fileBase64: fileBase64,
                                    fileName: (file['fileName'] ?? 'ملف مرفق').toString(),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.attach_file, color: isMe ? Colors.white : them.colorScheme.primary),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          file['fileName'] ?? "ملف مرفق",
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: isMe ? Colors.white : them.colorScheme.onSurface),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                    );
                  }),
                ),
              if ((message['text'] ?? '').isNotEmpty) Text(
                message['text'],
                style: TextStyle(
                  color: isMe ? Colors.white : them.colorScheme.onSurface,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 4),

              const SizedBox(height: 6),
              MessageReactionsWidget(
                consultationId: 'group_consultations',
                messageId: messageId,
                rootCollection: 'group_consultations',
                showAddButton: true,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatTimestamp(message['timestamp']),
                    style: TextStyle(color: isMe ? Colors.white70 : (isDarkMode? Colors.grey[300]:Colors.grey[600]), fontSize: 10),
                  ),
                  if (isMe)
                    Text(
                      '✓ تم الإرسال',
                      style: TextStyle(color: isMe ? Colors.white70 : (isDarkMode? Colors.grey[300]: Colors.grey[600]), fontSize: 10),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _messageFiles(Map<String, dynamic> message) {
    final rawFiles = message['files'];
    if (rawFiles is List && rawFiles.isNotEmpty) {
      return rawFiles
          .whereType<Map>()
          .map((file) => Map<String, dynamic>.from(file))
          .toList();
    }

    final type = (message['type'] ?? '').toString();
    final fileUrl = (message['fileUrl'] ?? '').toString();
    final fileBase64 = (message['fileBase64'] ?? '').toString();
    final fileName = (message['fileName'] ?? '').toString();
    if ((fileUrl.isEmpty && fileBase64.isEmpty) || fileName.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    return <Map<String, dynamic>>[
      {
        'fileType': type,
        'fileUrl': fileUrl,
        'fileBase64': fileBase64,
        'fileName': fileName,
      }
    ];
  }

  Widget _buildMessageInput() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: _showAttachmentSheet,
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'اكتب رسالتك...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: _isRecording ? Theme.of(context).colorScheme.error : MedicalTheme.primaryMedicalBlue,
            child: IconButton(
              icon: Icon(
                _messageController.text.trim().isEmpty && _selectedFiles.isEmpty
                    ? (_isRecording ? Icons.stop_circle_rounded : Icons.mic_rounded)
                    : Icons.send,
                color: Colors.white,
              ),
              onPressed: _isSending
                  ? null
                  : (_messageController.text.trim().isEmpty && _selectedFiles.isEmpty)
                      ? _toggleVoiceRecording
                      : _sendMessage,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final user = _auth.currentUser;
    if (user == null || (_messageController.text.trim().isEmpty && _selectedFiles.isEmpty)) return;

    setState(() => _isSending = true);

    try {
      final userData = await _firestore.collection("users").doc(user.uid).get();
      final fullName = userData.data()?['fullName'] ?? 'مستخدم';
      final photoURL = userData.data()?['photoURL'];

      final List<Map<String, String>> files = [];

      for (final file in _selectedFiles) {
        final uploadedFile = await _encodeGroupFileInline(file);
        files.add(uploadedFile);
      }

      final firstFile = files.isNotEmpty ? files.first : null;
      final msg = {
        'text': _messageController.text.trim(),
        'senderId': user.uid,
        'senderName': fullName,
        'senderImage': photoURL,
        'timestamp': FieldValue.serverTimestamp(),
        'files': files,
        'fileUrl': firstFile?['fileUrl'],
        'fileBase64': firstFile?['fileBase64'],
        'fileName': firstFile?['fileName'],
        'type': firstFile?['fileType'] ?? 'text',
        'status': 'sent',
        'reactions': <String, dynamic>{},
        'replyTo': _replyToMessage,
      };

      await _firestore.collection("group_consultations").add(msg);

      _messageController.clear();
      setState(() {
        _replyToMessage = null;
        _selectedFiles.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إرسال الرسالة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  bool _canStoreInline(int byteLength) => byteLength <= _maxInlineAttachmentBytes;

  Future<Map<String, String>> _encodeGroupFileInline(PlatformFile file) async {
    final ext = (file.extension ?? file.name.split('.').last).toLowerCase();
    final isImage = ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'webp';
    final isAudio = ext == 'm4a' || ext == 'mp3' || ext == 'wav' || ext == 'aac';
    final bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null || bytes.isEmpty) {
      throw Exception('الملف ${file.name} لا يحتوي بيانات');
    }
    if (!_canStoreInline(bytes.length)) {
      throw Exception('حجم الملف كبير جداً للإرسال داخل المحادثة بدون Firebase Storage');
    }
    return {
      'fileType': isAudio ? 'audio_inline' : (isImage ? 'image_inline' : 'file_inline'),
      'fileBase64': base64Encode(bytes),
      'fileName': file.name,
    };
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false, withData: true);
    if (result != null) setState(() => _selectedFiles = result.files);
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _imagePicker.pickImage(source: source);
    if (picked == null) return;
    setState(() {
      _selectedFiles = [
        PlatformFile(
          name: picked.name,
          path: picked.path,
          size: File(picked.path).lengthSync(),
        ),
      ];
    });
  }

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _attachmentAction(Icons.image_rounded, 'صورة', () => _pickImage(ImageSource.gallery)),
              _attachmentAction(Icons.camera_alt_rounded, 'كاميرا', () => _pickImage(ImageSource.camera)),
              _attachmentAction(Icons.attach_file_rounded, 'ملف', _pickFiles),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachmentAction(IconData icon, String label, VoidCallback action) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.pop(context);
        action();
      },
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 24, backgroundColor: MedicalTheme.primaryMedicalBlue.withOpacity(.12), child: Icon(icon, color: MedicalTheme.primaryMedicalBlue)),
            const SizedBox(height: 8),
            Text(label),
          ],
        ),
      ),
    );
  }


  Future<void> _toggleVoiceRecording() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      if (!mounted) return;
      setState(() => _isRecording = false);
      if (path == null) return;
      final file = File(path);
      if (!await file.exists()) {
        _showSnackBar('تعذر العثور على ملف التسجيل');
        return;
      }
      setState(() {
        _selectedFiles = [
          PlatformFile(
            name: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
            path: path,
            size: file.lengthSync(),
          ),
        ];
      });
      _showSnackBar('تم إرفاق التسجيل الصوتي، اضغط إرسال');
      return;
    }

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted || !await _audioRecorder.hasPermission()) {
      _showSnackBar('يلزم إذن الميكروفون لتسجيل الرسائل الصوتية');
      return;
    }
    final path = '${Directory.systemTemp.path}/group_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    if (mounted) setState(() => _isRecording = true);
  }

  Widget _buildAudioMessage({
    required String messageId,
    required String audioUrl,
    required String audioBase64,
    required ThemeData theme,
    required bool isMe,
  }) {
    final isPlaying = _playingMessageId == messageId;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isMe ? Colors.white.withOpacity(.16) : theme.colorScheme.primaryContainer.withOpacity(.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => _playOrPauseAudio(
              messageId: messageId,
              audioUrl: audioUrl.isNotEmpty ? audioUrl : null,
              inlineAudioBase64: audioBase64.isNotEmpty ? audioBase64 : null,
            ),
            icon: Icon(
              isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
              color: isMe ? Colors.white : theme.colorScheme.primary,
              size: 30,
            ),
          ),
          SizedBox(
            width: 140,
            child: Slider(
              value: (isPlaying && _audioDuration.inMilliseconds > 0)
                  ? _audioPosition.inMilliseconds.clamp(0, _audioDuration.inMilliseconds).toDouble()
                  : 0,
              max: _audioDuration.inMilliseconds > 0 ? _audioDuration.inMilliseconds.toDouble() : 1,
              onChanged: isPlaying
                  ? (value) => _audioPlayer.seek(Duration(milliseconds: value.toInt()))
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _playOrPauseAudio({
    required String messageId,
    String? audioUrl,
    String? inlineAudioBase64,
  }) async {
    try {
      if (_playingMessageId == messageId) {
        await _audioPlayer.pause();
        setState(() => _playingMessageId = null);
        return;
      }
      await _audioPlayer.stop();
      String? path;
      if (audioUrl != null && audioUrl.isNotEmpty) {
        path = await _downloadRemoteAudioToFile(messageId: messageId, audioUrl: audioUrl);
      }
      if (path == null && inlineAudioBase64 != null && inlineAudioBase64.isNotEmpty) {
        path = await _createInlineAudioFile(messageId: messageId, base64Data: inlineAudioBase64);
      }
      if (path == null) {
        _showSnackBar('لا يوجد ملف صوتي للتشغيل');
        return;
      }
      await _audioPlayer.play(DeviceFileSource(path));
      setState(() => _playingMessageId = messageId);
    } catch (_) {
      _showSnackBar('تعذر تشغيل الرسالة الصوتية');
    }
  }

  Future<String?> _downloadRemoteAudioToFile({required String messageId, required String audioUrl}) async {
    try {
      final response = await http.get(Uri.parse(audioUrl));
      if (response.statusCode != 200) return null;
      final path = '${Directory.systemTemp.path}/remote_group_voice_$messageId.m4a';
      await File(path).writeAsBytes(response.bodyBytes, flush: true);
      return path;
    } catch (_) {
      return null;
    }
  }

  Future<String> _createInlineAudioFile({required String messageId, required String base64Data}) async {
    if (_inlineAudioFiles.containsKey(messageId)) return _inlineAudioFiles[messageId]!;
    final path = '${Directory.systemTemp.path}/inline_group_voice_$messageId.m4a';
    await File(path).writeAsBytes(base64Decode(base64Data), flush: true);
    _inlineAudioFiles[messageId] = path;
    return path;
  }

  Future<void> _loadHiddenMessages() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _hiddenMessageIds = (prefs.getStringList(_hiddenMessagesKey) ?? <String>[]).toSet());
  }

  String get _hiddenMessagesKey => 'group_consultations_hidden_${_auth.currentUser?.uid ?? 'guest'}';

  Future<void> _saveHiddenMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenMessagesKey, _hiddenMessageIds.toList());
  }


  Future<void> _showMessageOptions(String messageId, Map<String, dynamic> message, bool isMe) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('رد على الرسالة'),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                title: const Text('حذف الرسالة من الطرفين'),
                onTap: () => Navigator.pop(context, 'delete'),
              )
            else
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('حذف من جهازي'),
                onTap: () => Navigator.pop(context, 'hide'),
              ),
          ],
        ),
      ),
    );
    if (selected == 'reply') {
      setState(() => _replyToMessage = message);
    } else if (selected == 'delete') {
      await _confirmDeleteMessage(messageId);
    } else if (selected == 'hide') {
      await _confirmHideMessage(messageId);
    }
  }

  Future<void> _confirmDeleteMessage(String messageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الرسالة'),
        content: const Text('هل تريد حذف الرسالة من الطرفين؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _firestore.collection('group_consultations').doc(messageId).delete();
    } catch (_) {
      _showSnackBar('فشل في حذف الرسالة');
    }
  }

  Future<void> _confirmHideMessage(String messageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المحادثة من جهازك؟'),
        content: const Text('سيتم إخفاء هذه الرسالة من جهازك فقط ولن تتأثر أجهزة المستخدمين الآخرين.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _hiddenMessageIds.add(messageId));
    await _saveHiddenMessages();
  }

  Future<void> _confirmHideAllMessages() async {
    final snapshot = await _firestore.collection("group_consultations").get();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف جميع المحادثات من جهازك؟'),
        content: const Text('سيتم إخفاء رسائل الاستشارة الجماعية الحالية من جهازك فقط بدون حذفها من Firebase أو من أجهزة الآخرين.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف الكل')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _hiddenMessageIds.addAll(snapshot.docs.map((doc) => doc.id)));
    await _saveHiddenMessages();
  }

  String _safeFileName(String fileName) {
    final safeName = fileName.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safeName.isEmpty ? 'group_attachment' : safeName;
  }

  String _resolveContentType(String extension, bool isImage) {
    if (isImage) return 'image/$extension';
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'zip':
        return 'application/zip';
      case 'rar':
        return 'application/vnd.rar';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _openGroupFile({
    required String messageId,
    required String fileUrl,
    required String fileBase64,
    required String fileName,
  }) async {
    try {
      final safeName = _safeFileName(fileName);
      final localPath = '${Directory.systemTemp.path}/group_${messageId}_$safeName';
      final file = File(localPath);

      if (fileUrl.trim().isNotEmpty) {
        final response = await http.get(Uri.parse(fileUrl.trim()));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('download_failed');
        }
        await file.writeAsBytes(response.bodyBytes, flush: true);
      } else if (fileBase64.isNotEmpty) {
        await file.writeAsBytes(base64Decode(fileBase64), flush: true);
      } else {
        throw Exception('missing_file');
      }

      final result = await OpenFilex.open(localPath);
      if (result.type == ResultType.noAppToOpen) {
        _showSnackBar('لا يوجد تطبيق مناسب لفتح هذا النوع من الملفات.');
      } else if (result.type != ResultType.done) {
        _showSnackBar('تعذر فتح الملف');
      }
    } catch (_) {
      _showSnackBar('تعذر فتح الملف');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) {
      final date = timestamp.toDate();
      return DateFormat('hh:mm a | dd MMM yyyy', 'ar').format(date);
    }
    return '';
  }
}

class ImagePreviewScreen extends StatelessWidget {
  final String imageUrl;
  final String imageBase64;
  const ImagePreviewScreen({super.key, required this.imageUrl, this.imageBase64 = ''});




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          child: imageUrl.isNotEmpty ? Image.network(imageUrl) : Image.memory(base64Decode(imageBase64)),
        ),
      ),
    );
  }
}
