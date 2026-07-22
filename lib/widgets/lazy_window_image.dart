import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/capture_image.dart';

class LazyWindowImage extends StatefulWidget {
  final SqlDatabase db;
  final int detailId;
  final String initialImagePath;
  final dynamic partitionsJson;
  final String? drawingImageBase64;
  final double height;
  final double width;
  final BoxFit fit;

  const LazyWindowImage({
    Key? key,
    required this.db,
    required this.detailId,
    required this.initialImagePath,
    required this.partitionsJson,
    this.drawingImageBase64,
    this.height = 140,
    this.width = double.infinity,
    this.fit = BoxFit.contain,
  }) : super(key: key);

  @override
  State<LazyWindowImage> createState() => _LazyWindowImageState();
}

class _LazyWindowImageState extends State<LazyWindowImage> {
  String? _resolvedPath;
  Uint8List? _decodedBytes;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(LazyWindowImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialImagePath != widget.initialImagePath ||
        oldWidget.detailId != widget.detailId ||
        oldWidget.partitionsJson != widget.partitionsJson ||
        oldWidget.drawingImageBase64 != widget.drawingImageBase64) {
      _resolveImage();
    }
  }

  Future<void> _resolveImage() async {
    // 1. Check if the initial path is valid and exists locally
    if (widget.initialImagePath.isNotEmpty) {
      final file = File(widget.initialImagePath);
      try {
        if (await file.exists()) {
          if (mounted) {
            setState(() {
              _resolvedPath = widget.initialImagePath;
              _decodedBytes = null;
              _isGenerating = false;
            });
          }
          return;
        }
      } catch (_) {}
    }

    // 2. Check if a base64 representation is synced from the cloud
    if (widget.drawingImageBase64 != null && widget.drawingImageBase64!.isNotEmpty) {
      try {
        final decoded = base64Decode(widget.drawingImageBase64!);
        if (mounted) {
          setState(() {
            _resolvedPath = null;
            _decodedBytes = decoded;
            _isGenerating = false;
          });
        }
        return;
      } catch (_) {}
    }

    // 3. Otherwise, if partitionsJson is available, try to generate it dynamically!
    final jsonRaw = widget.partitionsJson;
    if (jsonRaw == null) {
      if (mounted) {
        setState(() {
          _resolvedPath = null;
          _decodedBytes = null;
          _isGenerating = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isGenerating = true;
      });
    }

    try {
      Map<String, dynamic> modelMap = {};
      if (jsonRaw is Map<String, dynamic>) {
        modelMap = jsonRaw;
      } else if (jsonRaw is Map) {
        modelMap = Map<String, dynamic>.from(jsonRaw);
      } else {
        final str = jsonRaw.toString().trim();
        if (str.length >= 5) {
          modelMap = jsonDecode(str) as Map<String, dynamic>;
        }
      }

      if (modelMap.isNotEmpty) {
        final model = WindowModel(db: widget.db);
        await applyWindowModelAndLoadCatalog(model, modelMap);
        final newPath = await saveWindowImageToDisk(model);
        if (newPath.isNotEmpty) {
          // Update DB so we don't have to regenerate next time!
          await widget.db.updateCommandeDetailImagePath(widget.detailId, newPath);
          if (mounted) {
            setState(() {
              _resolvedPath = newPath;
              _decodedBytes = null;
              _isGenerating = false;
            });
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('LazyWindowImage Error generating image: $e');
    }

    if (mounted) {
      setState(() {
        _resolvedPath = null;
        _decodedBytes = null;
        _isGenerating = false;
      });
    }
  }

  Widget _buildPlaceholder() {
    return SizedBox(
      height: widget.height,
      width: widget.width,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined, color: Colors.grey, size: 28),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isGenerating) {
      return SizedBox(
        height: widget.height,
        width: widget.width,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_decodedBytes != null) {
      return Image.memory(
        _decodedBytes!,
        height: widget.height,
        width: widget.width,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }

    if (_resolvedPath == null || _resolvedPath!.isEmpty) {
      return _buildPlaceholder();
    }

    return Image.file(
      File(_resolvedPath!),
      height: widget.height,
      width: widget.width,
      fit: widget.fit,
      errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
    );
  }
}
