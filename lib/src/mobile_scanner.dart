import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/src/mobile_scanner_controller.dart';
import 'package:mobile_scanner/src/mobile_scanner_exception.dart';
import 'package:mobile_scanner/src/mobile_scanner_platform_interface.dart';
import 'package:mobile_scanner/src/objects/barcode_capture.dart';
import 'package:mobile_scanner/src/objects/mobile_scanner_state.dart';
import 'package:mobile_scanner/src/scan_window_calculation.dart';

import '../mobile_scanner.dart';

/// The function signature for the error builder.
typedef MobileScannerErrorBuilder = Widget Function(
  BuildContext,
  MobileScannerException,
  Widget?,
);

/// This widget displays a live camera preview for the barcode scanner.
class MobileScanner extends StatefulWidget {
  /// Create a new [MobileScanner] using the provided [controller].
  const MobileScanner({
    this.controller,
    this.onDetect,
    this.onDetectError = _onDetectErrorHandler,
    this.fit = BoxFit.cover,
    this.errorBuilder,
    this.overlayBuilder,
    this.placeholderBuilder,
    this.scanWindow,
    this.scanWindowUpdateThreshold = 0.0,
    this.startDelay = false,
    this.overlay,
    super.key,
  });

  /// The controller for the camera preview.
  final MobileScannerController? controller;

  /// The function that signals when new codes were detected by the [controller].
  ///
  /// To handle both [BarcodeCapture]s and [MobileScannerBarcodeException]s,
  /// use the [MobileScannerController.barcodes] stream directly (recommended),
  /// or provide a function to [onDetectError].
  final void Function(BarcodeCapture barcodes)? onDetect;

  /// The error handler equivalent for the [onDetect] function.
  ///
  /// If [onDetect] is not null, and this is null, errors are silently ignored.
  final void Function(Object error, StackTrace stackTrace) onDetectError;

  /// The error builder for the camera preview.
  ///
  /// If this is null, a black [ColoredBox],
  /// with a centered white [Icons.error] icon is used as error widget.
  final MobileScannerErrorBuilder? errorBuilder;

  /// The [BoxFit] for the camera preview.
  ///
  /// Defaults to [BoxFit.cover].
  final BoxFit fit;

  /// The builder for the overlay above the camera preview.
  ///
  /// The resulting widget can be combined with the [scanWindow] rectangle
  /// to create a cutout for the camera preview.
  ///
  /// The [BoxConstraints] for this builder
  /// are the same constraints that are used to compute the effective [scanWindow].
  ///
  /// The overlay is only displayed when the camera preview is visible.
  final LayoutWidgetBuilder? overlayBuilder;

  /// The placeholder builder for the camera preview.
  ///
  /// If this is null, a black [ColoredBox] is used as placeholder.
  ///
  /// The placeholder is displayed when the camera preview is being initialized.
  final Widget Function(BuildContext, Widget?)? placeholderBuilder;

  /// The scan window rectangle for the barcode scanner.
  ///
  /// If this is not null, the barcode scanner will only scan barcodes
  /// which intersect this rectangle.
  ///
  /// This rectangle is relative to the layout size
  /// of the *camera preview widget* in the widget tree,
  /// rather than the actual size of the camera preview output.
  /// This is because the size of the camera preview widget
  /// might not be the same as the size of the camera output.
  ///
  /// For example, the applied [fit] has an effect on the size of the camera preview widget,
  /// while the camera preview size remains the same.
  ///
  /// The following example shows a scan window that is centered,
  /// fills half the height and one third of the width of the layout:
  ///
  /// ```dart
  /// LayoutBuider(
  ///   builder: (BuildContext context, BoxConstraints constraints) {
  ///     final Size layoutSize = constraints.biggest;
  ///
  ///     final double scanWindowWidth = layoutSize.width / 3;
  ///     final double scanWindowHeight = layoutSize.height / 2;
  ///
  ///     final Rect scanWindow = Rect.fromCenter(
  ///       center: layoutSize.center(Offset.zero),
  ///       width: scanWindowWidth,
  ///       height: scanWindowHeight,
  ///     );
  ///   }
  /// );
  /// ```
  final Rect? scanWindow;

  /// The threshold for updates to the [scanWindow].
  ///
  /// If the [scanWindow] would be updated,
  /// due to new layout constraints for the scanner,
  /// and the width or height of the new scan window have not changed by this threshold,
  /// then the scan window is not updated.
  ///
  /// It is recommended to set this threshold
  /// if scan window updates cause performance issues.
  ///
  /// Defaults to no threshold for scan window updates.
  final double scanWindowUpdateThreshold;

  /// Only set this to true if you are starting another instance of mobile_scanner
  /// right after disposing the first one, like in a PageView.
  ///
  /// Default: false
  final bool startDelay;

  /// The overlay which will be painted above the scanner when has started successful.
  /// Will no be pointed when an error occurs or the scanner hasn't been started yet.
  final Widget? overlay;

  @override
  State<MobileScanner> createState() => _MobileScannerState();

  /// This empty function is used as the default error handler for [onDetect].
  static void _onDetectErrorHandler(Object error, StackTrace stackTrace) {
    // Do nothing.
  }
}

class _MobileScannerState extends State<MobileScanner>
    with WidgetsBindingObserver {
  late var controller = widget.controller ?? MobileScannerController();
  StreamSubscription<BarcodeCapture>? _barcodesSubscription;

  /// The current scan window.
  Rect? scanWindow;

  /// Calculate the scan window based on the given [constraints].
  ///
  /// If the [scanWindow] is already set, this method does nothing.
  void _maybeUpdateScanWindow(
    MobileScannerState scannerState,
    BoxConstraints constraints,
  ) {
    if (widget.scanWindow == null) {
      return;
    }

    final Rect newScanWindow = calculateScanWindowRelativeToTextureInPercentage(
      widget.fit,
      widget.scanWindow!,
      textureSize: scannerState.size,
      widgetSize: constraints.biggest,
    );

    // The scan window was never set before.
    // Set the initial scan window.
    if (scanWindow == null) {
      scanWindow = newScanWindow;

      unawaited(controller.updateScanWindow(scanWindow));

      return;
    }

    // The scan window did not not change.
    // The left, right, top and bottom are the same.
    if (scanWindow == newScanWindow) {
      return;
    }

    // The update threshold is not set, allow updating the scan window.
    if (widget.scanWindowUpdateThreshold == 0.0) {
      scanWindow = newScanWindow;

      unawaited(controller.updateScanWindow(scanWindow));

      return;
    }

    final double dx = (newScanWindow.width - scanWindow!.width).abs();
    final double dy = (newScanWindow.height - scanWindow!.height).abs();

    // The new scan window has changed enough, allow updating the scan window.
    if (dx >= widget.scanWindowUpdateThreshold ||
        dy >= widget.scanWindowUpdateThreshold) {
      scanWindow = newScanWindow;

      unawaited(controller.updateScanWindow(scanWindow));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: controller,
      builder: (BuildContext context, MobileScannerState? value, Widget? child) {
        if (value != null && !value.isInitialized) {
          const Widget defaultPlaceholder = ColoredBox(color: Colors.black);

          return widget.placeholderBuilder?.call(context, child) ??
              defaultPlaceholder;
        }

        if (value == null) {
          return _buildPlaceholderOrError(context, child);
        }

        /*final MobileScannerException? error = value.error;

        if (error != null) {
          const Widget defaultError = ColoredBox(
            color: Colors.black,
            child: Center(child: Icon(Icons.error, color: Colors.white)),
          );

          return widget.errorBuilder?.call(context, error, child) ??
              defaultError;
        }*/

        return LayoutBuilder(
          builder: (context, constraints) {

            if (widget.scanWindow != null && scanWindow == null) {
              scanWindow = calculateScanWindowRelativeToTextureInPercentage(
                widget.fit,
                widget.scanWindow!,
                textureSize: value.size,
                widgetSize: constraints.biggest,
              );

              controller.updateScanWindow(scanWindow);
            }
            _maybeUpdateScanWindow(value, constraints);

            final Size cameraPreviewSize = value.size;

            final Widget scannerWidget = ClipRect(
              child: SizedBox.fromSize(
                size: constraints.biggest,
                child: FittedBox(
                  fit: widget.fit,
                  child: SizedBox(
                    width: cameraPreviewSize.width,
                    height: cameraPreviewSize.height,
                    child: MobileScannerPlatform.instance.buildCameraView(),
                  ),
                ),
              ),
            );

            if (widget.overlay != null) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  scannerWidget,
                  widget.overlay!,
                ],
              );
            } else {
              return scannerWidget;
            }
          },
        );
      },
    );
  }

  StreamSubscription? _subscription;
  MobileScannerException? _startException;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = widget.controller ?? MobileScannerController();
    _startScanner();
  }

  Future<void> _startScanner() async {
    if (widget.startDelay) {
      await Future.delayed(const Duration(seconds: 1, milliseconds: 500));
    }

    _barcodesSubscription ??= controller.barcodes.listen(
      widget.onDetect,
    );

    if (!controller.autoStart) {
      debugPrint(
        'mobile_scanner: not starting automatically because autoStart is set to false in the controller.',
      );
      return;
    }

    controller.start().then((arguments) {
      // ignore: deprecated_member_use_from_same_package
      //widget.onStart?.call(arguments);
      //widget.onScannerStarted?.call(arguments);
    }).catchError((error) {
      if (!mounted) {
        return;
      }

      if (error is MobileScannerException) {
        _startException = error;
      } else if (error is PlatformException) {
        _startException = MobileScannerException(
          errorCode: MobileScannerErrorCode.genericError,
          errorDetails: MobileScannerErrorDetails(
            code: error.code,
            message: error.message,
            details: error.details,
          ),
        );
      } else {
        _startException = MobileScannerException(
          errorCode: MobileScannerErrorCode.genericError,
          errorDetails: MobileScannerErrorDetails(
            details: error,
          ),
        );
      }

      setState(() {});
    });
  }

  Widget _buildPlaceholderOrError(BuildContext context, Widget? child) {
    final error = _startException;

    if (error != null) {
      return widget.errorBuilder?.call(context, error, child) ??
          const ColoredBox(
            color: Colors.black,
            child: Center(child: Icon(Icons.error, color: Colors.white)),
          );
    }

    return widget.placeholderBuilder?.call(context, child) ??
        const ColoredBox(color: Colors.black);
  }

  @override
  void dispose() {
    super.dispose();

    if (_subscription != null) {
      _subscription!.cancel();
      _subscription = null;
    }

    if (controller.autoStart) {
      controller.stop();
    }
    // When this widget is unmounted, reset the scan window.
    unawaited(controller.updateScanWindow(null));

    // Dispose default controller if not provided by user
    if (widget.controller == null) {
      controller.dispose();
      WidgetsBinding.instance.removeObserver(this);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.controller != null || !controller.value.hasCameraPermission) {
      return;
    }

    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
      case AppLifecycleState.resumed:
        _subscription = controller.barcodes.listen(
          widget.onDetect,
          onError: widget.onDetectError,
          cancelOnError: false,
        );

        unawaited(controller.start());
      case AppLifecycleState.inactive:
        unawaited(_subscription?.cancel());
        _subscription = null;
        unawaited(controller.stop());
    }
  }
}
