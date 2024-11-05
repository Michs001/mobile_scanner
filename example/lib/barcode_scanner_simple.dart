import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:math';
import 'dart:ui';

class BarcodeScannerSimple extends StatefulWidget {
  const BarcodeScannerSimple({super.key});

  @override
  State<BarcodeScannerSimple> createState() => _BarcodeScannerSimpleState();
}

class _BarcodeScannerSimpleState extends State<BarcodeScannerSimple> {
  Barcode? _barcode;
  Set<Widget> detects = {};
  static const Size cameraResolution = Size(480, 640);
  MobileScannerController cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
  );

  @override
  void initState() {
    super.initState();
    cameraController.start();
  }

  Widget _buildBarcode(Barcode? value) {
    if (value == null) {
      return const Text(
        'Scan something!',
        overflow: TextOverflow.fade,
        style: TextStyle(color: Colors.white),
      );
    }

    return Text(
      value.displayValue ?? 'No display value.',
      overflow: TextOverflow.fade,
      style: const TextStyle(color: Colors.white),
    );
  }

  void _handleBarcode(BarcodeCapture barcodes) {
    if (mounted) {
      setState(() {
        _barcode = barcodes.barcodes.firstOrNull;
      });
    }
  }

  Iterable<Widget> Function(Barcode code) _getOverlayElements(double offsetX) {
    return (Barcode code) {
      Rect boundingBox = code.corners.boundingBox;

// Calculate the height of the bounding box
      double height = boundingBox.bottom - boundingBox.top;

// If the height is less than 40, adjust the bounding box to have a minimum height of 40
      if (height < 20) {
        double centerY = (boundingBox.bottom + boundingBox.top) / 2;
        double halfNewHeight = 30; // half of the desired minimum height
        double top = centerY - halfNewHeight;
        double bottom = centerY + halfNewHeight;

        // Update the bounding box with the new height
        boundingBox = Rect.fromLTRB(boundingBox.left, top, boundingBox.right, bottom);
      }

      return <Widget?>[
        AnimatedPositioned(
          //key: ValueKey<String?>(code.rawValue),
          left: boundingBox.left + offsetX,
          top: boundingBox.top - offsetX,
          duration: Durations.short1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.green.shade200,
                width: 5,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
            ),
            child: SizedBox.fromSize(
                size: boundingBox.size,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {},
                  child: Container(),
                )),
          ),
        ),
      ].whereType<Widget>();
    };
  }

  void executeWithDelay(Function function) {
    Future.delayed(Duration(milliseconds: 500), () {
      function();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Simple scanner')),
      backgroundColor: Colors.black,
      body:  LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return MobileScanner(
              startDelay: true,
              onDetect: (BarcodeCapture capture) {
                executeWithDelay(() {
                  final Iterable<Widget> Function(Barcode) getOverlayElements = _getOverlayElements((constraints.biggest.width - cameraResolution.width) / 2);

                  if (mounted) {
                    setState(() {
                      detects = capture.barcodes.toSet().expand<Widget>(getOverlayElements).toList().toSet();
                    });
                  }
                });
              },
              overlay: Stack(children: detects.toSet().toList()),
              controller: cameraController
          );
        },
      ),
    );
  }
}

extension GetBoundingBox on List<Offset> {
  Rect get boundingBox {
    return Rect.fromPoints(
      Offset(_reduceX(min), _reduceY(min)),
      Offset(_reduceX(max), _reduceY(max)),
    );
  }

  double _reduceX(
      double Function(double a, double b) reducer,
      ) =>
      map<double>((Offset o) => o.dx).reduce(reducer);

  double _reduceY(
      double Function(double a, double b) reducer,
      ) =>
      map<double>((Offset o) => o.dy).reduce(reducer);
}
