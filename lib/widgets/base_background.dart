import 'package:flutter/material.dart';

class BaseBackground extends StatelessWidget {
  final Widget child;
  
  const BaseBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity, 
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor, // ИСПРАВЛЕНИЕ: динамический фон
      ),
      child: child, 
    );
  }
}