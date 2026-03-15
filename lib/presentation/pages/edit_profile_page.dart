import 'package:flutter/material.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final TextEditingController _nameController = TextEditingController(text: "David Racer");
  final TextEditingController _usernameController = TextEditingController(text: "@david_racer");
  final TextEditingController _bioController = TextEditingController(text: "Car enthusiast. Mountain roads lover. 🏔️🏎️");
  final TextEditingController _linkController = TextEditingController(text: "cruiseconnect.com/david");

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Profil bearbeiten", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () {
              // Save logic here
              Navigator.pop(context);
            },
            child: const Text(
              "Speichern",
              style: TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          // Profilbild ändern
          Center(
            child: Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1C1F26),
                    shape: BoxShape.circle,
                  ),
                  child: const CircleAvatar(
                    radius: 50,
                    backgroundColor: Color(0xFF3A3E48),
                    child: Icon(Icons.person, size: 50, color: Colors.white),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF3B30), // Cruiser Red
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              "Bild ändern",
              style: TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 32),

          // Formular Felder
          _buildLabel("Anzeigename"),
          _buildTextField(_nameController, "Dein Name"),
          
          const SizedBox(height: 20),
          
          _buildLabel("Username"),
          _buildTextField(_usernameController, "@username"),
          const SizedBox(height: 6),
          const Text(
            'Du kannst deinen Benutzernamen nur alle 60 Tage ändern.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),

          const SizedBox(height: 20),

          _buildLabel("Steckbrief / Bio"),
          _buildTextField(_bioController, "Erzähl etwas über dich...", maxLines: 3),

          const SizedBox(height: 20),

          _buildLabel("Link / Webseite"),
          _buildTextField(_linkController, "https://..."),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text,
        style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, {int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}