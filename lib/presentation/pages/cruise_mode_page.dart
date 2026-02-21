import 'package:flutter/material.dart';

class CruiseModePage extends StatelessWidget {
  const CruiseModePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30),
              borderRadius: BorderRadius.circular(60),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF3B30).withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                )
              ],
            ),
            child: const Icon(
              Icons.directions_car,
              color: Colors.white,
              size: 60,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "Cruise Mode",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[900]?.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              "🔧 In Arbeit - Ein anderer Entwickler arbeitet daran",
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}