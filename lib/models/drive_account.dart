import 'package:flutter/material.dart';

enum DriveType {
  baidu('百度网盘', 'https://pan.baidu.com', Icons.cloud, Color(0xFF2932E1)),
  aliyun('阿里云盘', 'https://www.aliyundrive.com', Icons.cloud_circle, Color(0xFF6236FF)),
  pan123('123云盘', 'https://www.123pan.com', Icons.storage, Color(0xFFFF6B35)),
  quark('夸克网盘', 'https://pan.quark.cn', Icons.browser_updated, Color(0xFF2B85FF)),
  tianyi('天翼云盘', 'https://cloud.189.cn', Icons.signal_cellular_alt, Color(0xFFFF4D4F)),
  lanzou('蓝奏云', 'https://www.lanzou.com', Icons.upload_file, Color(0xFF00B96B)),
  caiyun('和彩云', 'https://caiyun.feixin.10086.cn', Icons.wifi, Color(0xFF0085FF)),
  ;

  final String label;
  final String loginUrl;
  final IconData icon;
  final Color color;
  const DriveType(this.label, this.loginUrl, this.icon, this.color);
}

class DriveAccount {
  final String id;
  final DriveType type;
  final String displayName;
  final String avatarUrl;
  final int usedSpace;
  final int totalSpace;
  final DateTime addedAt;

  const DriveAccount({
    required this.id,
    required this.type,
    this.displayName = '',
    this.avatarUrl = '',
    this.usedSpace = 0,
    this.totalSpace = 0,
    required this.addedAt,
  });

  DriveAccount copyWith({
    String? displayName,
    String? avatarUrl,
    int? usedSpace,
    int? totalSpace,
  }) {
    return DriveAccount(
      id: id,
      type: type,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      usedSpace: usedSpace ?? this.usedSpace,
      totalSpace: totalSpace ?? this.totalSpace,
      addedAt: addedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'usedSpace': usedSpace,
    'totalSpace': totalSpace,
    'addedAt': addedAt.toIso8601String(),
  };

  factory DriveAccount.fromJson(Map<String, dynamic> json) => DriveAccount(
    id: json['id'] as String,
    type: DriveType.values.firstWhere((e) => e.name == json['type'], orElse: () => DriveType.baidu),
    displayName: json['displayName'] as String? ?? '',
    avatarUrl: json['avatarUrl'] as String? ?? '',
    usedSpace: json['usedSpace'] as int? ?? 0,
    totalSpace: json['totalSpace'] as int? ?? 0,
    addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
  );
}
