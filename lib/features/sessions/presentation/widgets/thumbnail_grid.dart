import 'dart:io';

import 'package:flutter/material.dart';

import 'package:microscopeapp/models/frame_record.dart';

class ThumbnailGrid extends StatelessWidget {
  const ThumbnailGrid({
    super.key,
    required this.frames,
    required this.onOpen,
  });

  final List<FrameRecord> frames;
  final ValueChanged<FrameRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _columns(MediaQuery.sizeOf(context).width),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: frames.length,
        itemBuilder: (context, index) {
          final frame = frames[index];
          return _ThumbnailTile(frame: frame, onOpen: () => onOpen(frame));
        },
      ),
    );
  }

  int _columns(double width) {
    if (width >= 1000) {
      return 6;
    }
    if (width >= 700) {
      return 4;
    }
    return 3;
  }
}

class _ThumbnailTile extends StatelessWidget {
  const _ThumbnailTile({required this.frame, required this.onOpen});

  final FrameRecord frame;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final path = frame.filePath;
    return Semantics(
      button: true,
      label: 'Open frame ${frame.frameNumber}',
      child: Material(
        color: const Color(0xFF101716),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: path == null ? null : onOpen,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (path != null)
                Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  cacheWidth: 360,
                  errorBuilder: (context, error, stackTrace) => const _BrokenThumb(),
                )
              else
                const _BrokenThumb(),
              Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  margin: const EdgeInsets.all(6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xCC0B1212),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    frame.fileName,
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrokenThumb extends StatelessWidget {
  const _BrokenThumb();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF1C2827),
      child: Icon(Icons.broken_image_outlined),
    );
  }
}
