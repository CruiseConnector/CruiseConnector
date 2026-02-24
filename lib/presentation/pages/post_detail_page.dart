import 'package:flutter/material.dart';

class PostDetailPage extends StatelessWidget {
  final String name;
  final String handle;
  final String content;
  final String time;

  const PostDetailPage({
    super.key, 
    required this.name, 
    required this.handle,
    required this.content,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Beitrag", style: TextStyle(color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Original Post
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.grey[800], 
                  child: Text(name[0], style: const TextStyle(color: Colors.white))
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(handle, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Content (Groß)
            Text(content, style: const TextStyle(color: Colors.white, fontSize: 20, height: 1.4)),
            
            const SizedBox(height: 20),
            Text(
              "$time · CruiseConnect for iOS", 
              style: const TextStyle(color: Colors.grey, fontSize: 14)
            ),
            const Divider(color: Colors.white24),
            const SizedBox(height: 10),
            const Text("Kommentare", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 16),
            
            // Comments List
            _buildComment("Lisa", "Wow, sieht super aus! 🔥"),
            _buildComment("Tom", "Muss ich auch mal fahren."),
            _buildComment("Anna", "Wann ist das nächste Treffen?"),
          ],
        ),
      ),
      // Input for comment
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1F26),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  height: 45,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const TextField(
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Kommentar schreiben...",
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const CircleAvatar(
                backgroundColor: Color(0xFFFF3B30),
                radius: 22,
                child: Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComment(String user, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 16, backgroundColor: Colors.grey[800], child: Text(user[0], style: const TextStyle(color: Colors.white, fontSize: 12))),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1F26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(text, style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}