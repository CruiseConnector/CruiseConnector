import 'package:flutter/material.dart';

class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.people,
            size: 80,
            color: Color(0xFFFF3B30),
          ),
          const SizedBox(height: 20),
          const Text(
            "Community",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "Verbinde dich mit anderen CruiseConnect Nutzern",
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}