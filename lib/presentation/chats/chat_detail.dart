import 'dart:developer';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tz_chat_app/provider/chat_provider.dart';
import 'package:path_provider/path_provider.dart';

class ChatDetail extends StatefulWidget {
  final String receiverId;

  const ChatDetail({super.key, required this.receiverId});

  @override
  State<ChatDetail> createState() => _ChatDetailState();
}

class _ChatDetailState extends State<ChatDetail> {
  final TextEditingController _messageController = TextEditingController();
  final ChatProvider _chatProvider = ChatProvider();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecording = false;
  File? _imageFile;
  String? _audioFilePath;

  @override
  void initState() {
    super.initState();
    initRecorder();
  }

  Future<void> initRecorder() async {
    try {
      await _recorder.openRecorder();
    } catch (e) {
      print('Failed to open recorder: $e');
    }
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    super.dispose();
  }

  void _sendMessage() async {
    String? imageUrl;
    if (_imageFile != null) {
      imageUrl = await _uploadImage(_imageFile!);
    }

    String? audioUrl;
    if (_audioFilePath != null) {
      audioUrl = await _uploadAudio(File(_audioFilePath!));
    }

    if (_messageController.text.isNotEmpty ||
        imageUrl != null ||
        audioUrl != null) {
      await _chatProvider.sendMessage(
        widget.receiverId,
        _messageController.text,
        imageUrl: imageUrl,
        audioUrl: audioUrl,
      );

      _messageController.clear();
      setState(() {
        _imageFile = null;
        _audioFilePath = null;
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  Future<String> _uploadImage(File image) async {
    String fileName = '${DateTime.now().millisecondsSinceEpoch}.png';
    Reference storageRef =
        FirebaseStorage.instance.ref().child('chat_images/$fileName');
    UploadTask uploadTask = storageRef.putFile(image);
    TaskSnapshot taskSnapshot = await uploadTask;
    return await taskSnapshot.ref.getDownloadURL();
  }

  Future<String> _uploadAudio(File audio) async {
    String fileName = '${DateTime.now().millisecondsSinceEpoch}.aac';
    Reference storageRef =
        FirebaseStorage.instance.ref().child('chat_audios/$fileName');
    UploadTask uploadTask = storageRef.putFile(audio);
    TaskSnapshot taskSnapshot = await uploadTask;
    return await taskSnapshot.ref.getDownloadURL();
  }

  Future<void> _startRecording() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      await Permission.microphone.request();
    }

    status = await Permission.microphone.status; // Check again after requesting
    if (status.isGranted) {
      Directory tempDir = await getTemporaryDirectory();
      String path =
          '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.aac';

      try {
        await _recorder.startRecorder(toFile: path);
        setState(() {
          _isRecording = true;
        });
      } catch (e) {
        log(e.toString(), name: '_startRecording');
      }
    } else {}
  }

  Future<void> _stopRecording() async {
    String? path = await _recorder.stopRecorder();
    setState(() {
      _isRecording = false;
      _audioFilePath = path;
    });
  }

  Future<Map<String, dynamic>?> _fetchReceiverData() async {
    try {
      DocumentSnapshot snapshot =
          await _firestore.collection('users').doc(widget.receiverId).get();
      return snapshot.data() as Map<String, dynamic>?;
    } catch (e) {
      return null;
    }
  }

  String _formatDate(DateTime dateTime) {
    return DateFormat('dd.MM.yy').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchReceiverData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError || snapshot.data == null) {
          return const Scaffold(
              body: Center(child: Text('Ошибка загрузки данных пользователя')));
        }

        Map<String, dynamic> receiverData = snapshot.data!;
        String firstName = receiverData['firstName'] ?? '';
        String lastName = receiverData['lastName'] ?? '';
        String initials =
            "${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}";
        bool isOnline = receiverData['isOnline'] ?? false;

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            surfaceTintColor: Colors.white,
            leading: IconButton(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: const Icon(Icons.arrow_back_ios),
            ),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF3BEC78),
                  child: Text(initials),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("$firstName $lastName",
                        style: const TextStyle(color: Colors.black)),
                    Text(isOnline ? 'в сети' : 'не в сети',
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 12)),
                  ],
                ),
              ],
            ),
            elevation: 0,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Divider(
                thickness: 0.33,
                color: Colors.black.withOpacity(0.30000001192092896),
              ),
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 29.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: _buildMessageList()),
                if (_imageFile != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Stack(
                      alignment: Alignment.topRight,
                      children: [
                        Image.file(_imageFile!),
                        IconButton(
                          icon: const Icon(Icons.cancel, color: Colors.red),
                          onPressed: () {
                            setState(() {
                              _imageFile = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                if (_audioFilePath != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDF2F6),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Center(child: Text('Аудиозапись')),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel, color: Colors.red),
                          onPressed: () {
                            setState(() {
                              _audioFilePath = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                _buildTextInputField(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextInputField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Row(
        children: [
          IconButton(
            icon: Container(
              width: 42,
              height: 42,
              padding: const EdgeInsets.all(6),
              clipBehavior: Clip.antiAlias,
              decoration: ShapeDecoration(
                color: const Color(0xFFEDF2F6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Image.asset('assets/icons/Attach.png'),
            ),
            onPressed: _pickImage,
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.only(left: 12),
                hintText: 'Сообщение',
                hintStyle: const TextStyle(
                  color: Color(0xFF9DB6CA),
                  fontSize: 16,
                  fontFamily: 'Gilroy',
                  fontWeight: FontWeight.w500,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: const Color(0xFFEDF2F6),
              ),
              onChanged: (text) {
                setState(() {});
              },
            ),
          ),
          IconButton(
            icon: Container(
              width: 42,
              height: 42,
              padding: const EdgeInsets.all(6),
              clipBehavior: Clip.antiAlias,
              decoration: ShapeDecoration(
                color: const Color(0xFFEDF2F6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child:
                  _messageController.text.isNotEmpty || _audioFilePath != null
                      ? const Icon(Icons.send, color: Colors.green)
                      : _isRecording
                          ? const Icon(Icons.stop, color: Colors.red)
                          : const Icon(Icons.mic, color: Colors.blue),
            ),
            onPressed:
                _messageController.text.isNotEmpty || _audioFilePath != null
                    ? _sendMessage
                    : _isRecording
                        ? _stopRecording
                        : _startRecording,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return StreamBuilder(
      stream: _chatProvider.getMessages(
          widget.receiverId, _firebaseAuth.currentUser!.uid),
      builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (snapshot.hasError) {
          return Text('Ошибка: ${snapshot.error}');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        var messages = snapshot.data?.docs ?? [];
        messages = messages.reversed.toList();

        return ListView.builder(
          reverse: true,
          itemCount: messages.length,
          itemBuilder: (context, index) {
            DocumentSnapshot currentMessage = messages[index];
            bool showDateSeparator = false;

            if (index == messages.length - 1) {
              showDateSeparator = true;
            } else {
              DateTime currentMessageDate =
                  messages[index]['timestamp'].toDate();
              DateTime nextMessageDate =
                  messages[index + 1]['timestamp'].toDate();
              if (_formatDate(currentMessageDate) !=
                  _formatDate(nextMessageDate)) {
                showDateSeparator = true;
              }
            }

            return Column(
              children: [
                if (showDateSeparator)
                  _dateSeparator(currentMessage['timestamp'].toDate()),
                _buildMessageItem(currentMessage),
              ],
            );
          },
        );
      },
    );
  }

  Widget _dateSeparator(DateTime dateTime) {
    String formattedDate = _formatDate(dateTime);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Expanded(
            child: Divider(
              color: Color(0xFF9DB6CA),
              thickness: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              formattedDate,
              style: const TextStyle(
                color: Color(0xFF9DB6CA),
                fontSize: 14,
                fontFamily: 'Gilroy',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Expanded(
            child: Divider(
              color: Color(0xFF9DB6CA),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(DocumentSnapshot document) {
    Map<String, dynamic> data = document.data() as Map<String, dynamic>;
    bool isMe = data['senderId'] == _firebaseAuth.currentUser!.uid;

    Timestamp timestamp = data['timestamp'];
    DateTime dateTime = timestamp.toDate();
    String formattedTime = DateFormat('HH:mm').format(dateTime);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        padding: const EdgeInsets.only(top: 6, left: 6, right: 4, bottom: 6),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF3BEC78) : const Color(0xFFEDF2F6),
          borderRadius: isMe
              ? const BorderRadius.only(
                  topLeft: Radius.circular(21),
                  topRight: Radius.circular(21),
                  bottomLeft: Radius.circular(21),
                )
              : const BorderRadius.only(
                  topLeft: Radius.circular(21),
                  topRight: Radius.circular(21),
                  bottomRight: Radius.circular(21),
                ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              spreadRadius: 0.5,
              blurRadius: 2,
              offset: const Offset(0, 0.75),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (data['imageUrl'] != null)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(19),
                  topRight: Radius.circular(19),
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                child: Image.network(
                  data['imageUrl'],
                  fit: BoxFit.cover,
                ),
              ),
            if (data['message'].isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      data['message'],
                      style: const TextStyle(
                        color: Color(0xFF00521B),
                        fontSize: 14,
                        fontFamily: 'Gilroy',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Opacity(
                      opacity: 0.80,
                      child: Text(
                        formattedTime,
                        style: const TextStyle(
                          color: Color(0xFF00521B),
                          fontSize: 12,
                          fontFamily: 'Gilroy',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (data['audioUrl'] != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.play_arrow),
                      onPressed: () {
                        // Logic to play the audio
                      },
                    ),
                    Text(
                      formattedTime,
                      style: const TextStyle(
                        color: Color(0xFF00521B),
                        fontSize: 12,
                        fontFamily: 'Gilroy',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
