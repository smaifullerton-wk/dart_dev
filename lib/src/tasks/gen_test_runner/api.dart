// Copyright 2015 Workiva Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

library dart_dev.src.tasks.gen_test_runner.api;

import 'dart:async';
import 'dart:io';

import 'package:dart_dev/src/tasks/gen_test_runner/config.dart';
import 'package:dart_dev/src/tasks/task.dart';

Future<GenTestRunnerTask> genTestRunner(TestRunnerConfig currentConfig) async {
  var taskTitle = 'gen-test-runner';
  var args = ['-d ${currentConfig.directory}', '-e ${currentConfig.env}'];
  currentConfig.genHtml ? args.add('--genHtml') : args.add('--no-genHtml');

  GenTestRunnerTask task =
      new GenTestRunnerTask('$taskTitle ${args.join(' ')}');

  var currentDirectory = currentConfig.directory;
  if (!currentDirectory.endsWith('/')) {
    currentDirectory += '/';
  }

  File generatedRunner =
      new File('${currentDirectory}/${currentConfig.filename}.dart');

  List<String> existingLines;
  if (currentConfig.check) {
    try {
      existingLines = generatedRunner.readAsStringSync().split('\n');
    } catch (_) {
      existingLines = [];
    }
  }

  List<String> runnerLines = [];

  Directory testDirectory = new Directory(currentDirectory);
  List<File> testFiles = [];
  List<File> allFiles = testDirectory
      .listSync(recursive: true, followLinks: false)
      .where((FileSystemEntity entity) => entity is File)
      .toList();
  allFiles.sort((File left, File right) => left.path.compareTo(right.path));
  allFiles
      .where((File entity) =>
          !entity.path.endsWith('${currentConfig.filename}.dart'))
      .forEach((File entity) {
    if (entity.path.endsWith('_test.dart')) {
      testFiles.add(entity);
      task.testFiles.add(entity.path);
    } else if (entity.path.endsWith('.dart')) {
      task.excludedFiles.add(entity.path);
    }
  });

  if (currentConfig.env == Environment.browser) {
    if (currentConfig.genHtml) {
      await testHtmlFileGenerator(
          currentDirectory, currentConfig.filename, currentConfig.htmlHeaders);
    }
    runnerLines.add('@TestOn(\'browser\')');
  } else {
    runnerLines.add('@TestOn(\'vm\')');
  }
  runnerLines.add(
      'library ${currentDirectory.replaceAll('/','.')}${currentConfig.filename};');
  runnerLines.add('');

  testFiles.forEach((File file) {
    var testPath = file.path.replaceFirst(currentDirectory, '');
    runnerLines.add(
        'import \'${'./'+testPath}\' as ${testPath.replaceAll('/','_').substring(0, testPath.length - 5)};');
  });

  runnerLines.add('import \'package:test/test.dart\';');

  if (currentConfig.dartHeaders.isNotEmpty) {
    currentConfig.dartHeaders.forEach((String header) {
      runnerLines.add(header);
    });
  }

  runnerLines.add('');
  runnerLines.add('void main() {');

  if (currentConfig.preTestCommands.isNotEmpty) {
    currentConfig.preTestCommands.forEach((String command) {
      runnerLines.add('  $command');
    });
  }

  testFiles.forEach((File file) {
    var testPath = file.path.replaceFirst(currentDirectory, '');
    runnerLines.add(
        '  ${testPath.replaceAll('/','_').substring(0, testPath.length - 5)}.main();');
  });

  runnerLines.add('}');
  String updatedContent = runnerLines.join('\n');

  task.runnerFile = generatedRunner.path;

  if (currentConfig.check) {
    task.newLength = runnerLines.length;
    task.oldLength = existingLines.length;

    bool success = true;
    if (existingLines.length != runnerLines.length) {
      success = false;
    }
    for (int i = 0; i < existingLines.length; i++) {
      if (existingLines[i] != runnerLines[i]) {
        success = false;
        task.mismatchedLineNumber = i + 1;
        task.newMismatchedLine = runnerLines[i];
        task.oldMismatchedLine = existingLines[i];
        break;
      }
    }
    task.successful = success;
  } else {
    generatedRunner.writeAsStringSync(updatedContent);
    task.successful = true;
  }

  return task;
}

Future testHtmlFileGenerator(
    String directory, String filename, List<String> htmlHeaders) async {
  File generatedRunner = new File('$directory/$filename.html');
  IOSink writer = generatedRunner.openWrite(mode: FileMode.WRITE);
  writer.writeln('<!DOCTYPE html>');
  writer.writeln('<html>');
  writer.writeln('  <head>');
  writer.writeln('    <title>$filename</title>');
  htmlHeaders.forEach((header) {
    writer.writeln('    $header');
  });
  writer.writeln('    <link rel="x-dart-test"  href="$filename.dart">');
  writer.writeln('    <script src="packages/test/dart.js"></script>');
  writer.writeln('  </head>');
  writer.writeln('  <body></body>');
  writer.writeln('</html>');
  await writer.close();
}

class GenTestRunnerTask extends Task {
  final Future done = new Future.value();
  List<String> excludedFiles = [];
  final String generateCommand;
  List<String> testFiles = [];
  int newLength;
  int oldLength;
  int mismatchedLineNumber;
  String newMismatchedLine = '';
  String oldMismatchedLine = '';
  String runnerFile;

  GenTestRunnerTask(String this.generateCommand);
}
