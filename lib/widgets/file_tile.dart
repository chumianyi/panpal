import 'package:flutter/material.dart';
import '../models/cloud_file.dart';
import '../utils/format_utils.dart';

class FileTile extends StatelessWidget {
  final CloudFile file;
  final bool selected;
  final bool selectMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDownload;
  final VoidCallback onShare;

  const FileTile({
    super.key,
    required this.file,
    required this.selected,
    required this.selectMode,
    required this.onTap,
    required this.onLongPress,
    required this.onDownload,
    required this.onShare,
  });

  IconData get _icon {
    if (file.isDir) return Icons.folder;
    switch (file.extension) {
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp': case 'bmp': return Icons.image;
      case 'mp4': case 'mkv': case 'avi': case 'mov': case 'flv': case 'wmv': return Icons.movie;
      case 'mp3': case 'flac': case 'wav': case 'aac': case 'ogg': return Icons.music_note;
      case 'pdf': return Icons.picture_as_pdf;
      case 'doc': case 'docx': return Icons.description;
      case 'xls': case 'xlsx': return Icons.table_chart;
      case 'ppt': case 'pptx': return Icons.slideshow;
      case 'zip': case 'rar': case '7z': case 'tar': case 'gz': return Icons.archive;
      case 'txt': case 'md': return Icons.text_snippet;
      case 'apk': return Icons.android;
      case 'exe': return Icons.desktop_windows;
      default: return Icons.insert_drive_file;
    }
  }

  Color get _iconColor {
    if (file.isDir) return Colors.orange;
    switch (file.extension) {
      case 'jpg': case 'jpeg': case 'png': case 'gif': return Colors.purple;
      case 'mp4': case 'mkv': case 'avi': return Colors.red;
      case 'mp3': case 'flac': return Colors.pink;
      case 'pdf': return Colors.redAccent;
      case 'zip': case 'rar': case '7z': return Colors.brown;
      default: return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: selectMode
          ? Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, color: selected ? Theme.of(context).colorScheme.primary : Colors.grey)
          : Icon(_icon, color: _iconColor, size: 36),
      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
      subtitle: Text(
        file.isDir ? '文件夹' : '${FormatUtils.fileSize(file.size)} · ${FormatUtils.dateTime(file.modifiedAt)}',
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      trailing: selectMode
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!file.isDir)
                  IconButton(icon: const Icon(Icons.download, size: 20), onPressed: onDownload, tooltip: '下载'),
                IconButton(icon: const Icon(Icons.share, size: 20), onPressed: onShare, tooltip: '分享'),
              ],
            ),
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
    );
  }
}
