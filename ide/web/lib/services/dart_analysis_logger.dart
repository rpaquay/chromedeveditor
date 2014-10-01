// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.dart_analysis_logger;

class AnalysisLogger {
 static final AnalysisLogger instance = new AnalysisLogger();

 void debug(String text) {
   print("${text}");
 }
}
