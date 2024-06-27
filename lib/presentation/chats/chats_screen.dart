import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tz_chat_app/presentation/chats/chat_detail.dart';
import 'package:tz_chat_app/presentation/registration/registration_screen.dart';
import 'package:tz_chat_app/provider/chat_provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:tz_chat_app/services/auth_service.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  Timer? _timer;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (Timer t) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String formatChatTime(dynamic lastActive) {
    if (lastActive == null) {
      return 'Неизвестно';
    }

    DateTime dateTime;
    if (lastActive is DateTime) {
      dateTime = lastActive;
    } else if (lastActive is String) {
      dateTime = DateTime.tryParse(lastActive) ?? DateTime.now();
    } else {
      return 'Некорректные данные';
    }

    Duration difference = DateTime.now().difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Только что';
    } else {
      return timeago.format(dateTime, locale: 'ru');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        surfaceTintColor: Colors.white,
        backgroundColor: Colors.white,
        title: const Text(
          'Чаты',
          style: TextStyle(
            color: Color(0xFF2B333E),
            fontSize: 32,
            fontFamily: 'Gilroy',
            fontWeight: FontWeight.w600,
            height: 0,
          ),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black),
            onPressed: () {
              final authService =
                  Provider.of<AuthService>(context, listen: false);
              authService.signOut();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => const RegistrationScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 20.0,
        ),
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.only(left: 8),
                hintText: 'Поиск',
                hintStyle: const TextStyle(
                  color: Color(0xFF9DB6CA),
                  fontSize: 16,
                  fontFamily: 'Gilroy',
                  fontWeight: FontWeight.w500,
                  height: 0,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: Color(0xFF9DB6CA),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: const Color(0xFFEDF2F6),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream:
                    FirebaseFirestore.instance.collection('users').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Text("Error: ${snapshot.error}");
                  }

                  if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                    return ListView(
                      children: snapshot.data!.docs
                          .map<Widget>((doc) => _buildUserListItem(doc))
                          .toList(),
                    );
                  } else {
                    return const Center(child: Text("No users found"));
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserListItem(DocumentSnapshot document) {
    Map<String, dynamic> data = document.data() as Map<String, dynamic>;
    if (_auth.currentUser!.uid != data['uid']) {
      String firstName = data['firstName'] ?? '';
      String lastName = data['lastName'] ?? '';
      String initials =
          "${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}";

      return FutureBuilder<DocumentSnapshot>(
        future: Provider.of<ChatProvider>(context, listen: false)
            .getLastMessage(_auth.currentUser!.uid, data['uid']),
        builder: (context, snapshot) {
          String lastMessage = "Загрузка...";
          String lastMessageTime = "Неизвестно";
          if (snapshot.connectionState == ConnectionState.done) {
            if (snapshot.hasData && snapshot.data!.exists) {
              var messageData = snapshot.data!.data() as Map<String, dynamic>;
              lastMessage = messageData['message'];
              lastMessageTime =
                  formatChatTime(messageData['timestamp'].toDate());
            } else {
              lastMessage = "Нет сообщений";
            }
          }

          return ListTile(
            contentPadding: const EdgeInsets.only(top: 14),
            leading: CircleAvatar(
              backgroundColor: Colors.green,
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontFamily: 'Gilroy',
                  fontWeight: FontWeight.w700,
                  height: 0,
                ),
              ),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "$firstName $lastName",
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 15,
                    fontFamily: 'Gilroy',
                    fontWeight: FontWeight.w600,
                    height: 0,
                  ),
                ),
                Text(
                  lastMessageTime,
                  style: const TextStyle(
                    color: Color(0xFF5D7A90),
                    fontSize: 12,
                    fontFamily: 'Gilroy',
                    fontWeight: FontWeight.w500,
                    height: 0,
                  ),
                ),
              ],
            ),
            subtitle: Text(
              "$lastMessage,",
              style: const TextStyle(
                color: Color(0xFF5D7A90),
                fontSize: 12,
                fontFamily: 'Gilroy',
                fontWeight: FontWeight.w500,
                height: 0,
              ),
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatDetail(receiverId: data['uid']),
                ),
              );
            },
          );
        },
      );
    } else {
      return const SizedBox();
    }
  }
}
