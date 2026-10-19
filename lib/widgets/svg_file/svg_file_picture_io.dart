import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

Widget svgFilePicture(
  String path, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
  WidgetBuilder? placeholderBuilder,
}) => SvgPicture.file(File(path), width: width, height: height, fit: fit,
    placeholderBuilder: placeholderBuilder);
