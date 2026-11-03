import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'capture_cleanup.dart';

class FaceCapture {
  const FaceCapture({required this.bytes, required this.filename});
  final Uint8List bytes;
  final String filename;
}

abstract interface class SelfieCamera {
  Future<void> initialize();
  Widget buildPreview();
  Future<FaceCapture> capture();
  Future<void> close();
}

typedef SelfieCameraFactory = SelfieCamera Function();
typedef FaceDocumentPicker = Future<FaceCapture?> Function();

class DeviceSelfieCamera implements SelfieCamera {
  CameraController? _controller;

  @override
  Future<void> initialize() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw CameraException('no_camera', 'No hay una cámara disponible.');
    }
    final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first);
    final controller =
        CameraController(camera, ResolutionPreset.high, enableAudio: false);
    _controller = controller;
    await controller.initialize();
  }

  @override
  Widget buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<CameraValue>(
        valueListenable: controller,
        builder: (context, value, child) {
          final orientation = value.previewPauseOrientation ??
              value.lockedCaptureOrientation ??
              value.deviceOrientation;
          final landscape = orientation == DeviceOrientation.landscapeLeft ||
              orientation == DeviceOrientation.landscapeRight;
          final ratio = landscape ? value.aspectRatio : 1 / value.aspectRatio;
          return LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = width / ratio;
            return ClipRect(
                child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                        width: width,
                        height: height,
                        child: CameraPreview(controller))));
          });
        });
  }

  @override
  Future<FaceCapture> capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw CameraException('camera_not_ready', 'La cámara no está preparada.');
    }
    final image = await controller.takePicture();
    try {
      return FaceCapture(
          bytes: await image.readAsBytes(), filename: image.name);
    } finally {
      await releaseCapturedImage(image.path);
    }
  }

  @override
  Future<void> close() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}

Future<FaceCapture?> pickFaceDocument() async {
  final document = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      maxHeight: 1800,
      imageQuality: 90,
      requestFullMetadata: false);
  if (document == null) return null;
  return FaceCapture(
      bytes: await document.readAsBytes(), filename: document.name);
}
