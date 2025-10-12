import 'package:flutter/material.dart';
import '../utils/database_helper_hybrid.dart';

/// API连接状态指示器
class ApiStatusIndicator extends StatefulWidget {
  const ApiStatusIndicator({super.key});

  @override
  State<ApiStatusIndicator> createState() => _ApiStatusIndicatorState();
}

class _ApiStatusIndicatorState extends State<ApiStatusIndicator> {
  bool _isApiAvailable = false;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _checkApiStatus();
  }

  Future<void> _checkApiStatus() async {
    if (!mounted) return;
    
    setState(() => _isChecking = true);
    
    try {
      final isAvailable = await DatabaseHelperHybrid.instance.checkApiAvailable();
      if (mounted) {
        setState(() {
          _isApiAvailable = isAvailable;
          _isChecking = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isApiAvailable = false;
          _isChecking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return GestureDetector(
      onTap: _checkApiStatus,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _isApiAvailable ? Colors.green : Colors.orange,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isApiAvailable ? Icons.cloud_done : Icons.cloud_off,
              size: 14,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              _isApiAvailable ? '云端' : '本地',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}