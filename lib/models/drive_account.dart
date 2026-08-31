import 'package:flutter/material.dart';

enum DriveType {
  pan123,
  lanzou,
  baidu,
  aliyun,
  quark,
  tianyi,
}

extension DriveTypeInfo on DriveType {
  String get label {
    switch (this) {
      case DriveType.pan123:
        return '123云盘';
      case DriveType.lanzou:
        return '蓝奏云';
      case DriveType.baidu:
        return '百度网盘';
      case DriveType.aliyun:
        return '阿里云盘';
      case DriveType.quark:
        return '夸克网盘';
      case DriveType.tianyi:
        return '天翼云盘';
    }
  }

  String get loginUrl {
    switch (this) {
      case DriveType.pan123:
        return 'https://www.123pan.com/';
      case DriveType.lanzou:
        return 'https://www.lanzou.com/';
      case DriveType.baidu:
        return 'https://pan.baidu.com/';
      case DriveType.aliyun:
        return 'https://www.aliyundrive.com/';
      case DriveType.quark:
        return 'https://pan.quark.cn/';
      case DriveType.tianyi:
        return 'https://cloud.189.cn/';
    }
  }

  IconData get icon {
    switch (this) {
      case DriveType.pan123:
        return Icons.cloud;
      case DriveType.lanzou:
        return Icons.link;
      case DriveType.baidu:
        return Icons.folder;
      case DriveType.aliyun:
        return Icons.cloud_done;
      case DriveType.quark:
        return Icons.bolt;
      case DriveType.tianyi:
        return Icons.wifi;
    }
  }

  Color get color {
    switch (this) {
      case DriveType.pan123:
        return const Color(0xFF2196F3);
      case DriveType.lanzou:
        return const Color(0xFF00BCD4);
      case DriveType.baidu:
        return const Color(0xFF4CAF50);
      case DriveType.aliyun:
        return const Color(0xFFFF6B35);
      case DriveType.quark:
        return const Color(0xFF2B85FF);
      case DriveType.tianyi:
        return const Color(0xFFFF9800);
    }
  }

  bool get supportsFileList {
    switch (this) {
      case DriveType.lanzou:
        return false;
      default:
        return true;
    }
  }

  bool get supportsPasswordLogin => this == DriveType.pan123;

  bool get isParserOnly => this == DriveType.lanzou;
}

class DriveAccount {
  final String id;
  final DriveType type;
  final String displayName;
  final int usedSpace;
  final int totalSpace;
  final DateTime addedAt;
  final Map<String, dynamic> credential;

  const DriveAccount({
    required this.id,
    required this.type,
    this.displayName = '',
    this.usedSpace = 0,
    this.totalSpace = 0,
    required this.addedAt,
    this.credential = const {},
  });

  DriveAccount copyWith({
    String? displayName,
    int? usedSpace,
    int? totalSpace,
    Map<String, dynamic>? credential,
  }) {
    return DriveAccount(
      id: id,
      type: type,
      displayName: displayName ?? this.displayName,
      usedSpace: usedSpace ?? this.usedSpace,
      totalSpace: totalSpace ?? this.totalSpace,
      addedAt: addedAt,
      credential: credential ?? this.credential,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'displayName': displayName,
        'usedSpace': usedSpace,
        'totalSpace': totalSpace,
        'addedAt': addedAt.toIso8601String(),
        'credential': credential,
      };

  factory DriveAccount.fromJson(Map<String, dynamic> json) => DriveAccount(
        id: json['id'] as String,
        type: DriveType.values[json['type'] as int],
        displayName: json['displayName'] as String? ?? '',
        usedSpace: json['usedSpace'] as int? ?? 0,
        totalSpace: json['totalSpace'] as int? ?? 0,
        addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
        credential: Map<String, dynamic>.from(json['credential'] as Map? ?? {}),
      );
}
