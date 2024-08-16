import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:process_run/shell.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'package:window_manager/window_manager.dart';
import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:path/path.dart' as path;

enum ProjectType {
  flutter,
  gradle,
  html,
  java,
  net,
  nodejs,
  python,
  rust,
  unity,
  unknown,
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    WindowManager.instance.setMinimumSize(const Size(740, 460));
    WindowManager.instance.setMaximumSize(const Size(740, 460));
  }
  runApp(const CodeLauncher());
}

class CodeLauncher extends StatelessWidget {
  const CodeLauncher({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      //theme: ThemeData(useMaterial3: false),
      home: const MyHomePage(),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: false),
      darkTheme: ThemeData(useMaterial3: false),
      themeMode: ThemeMode.dark,
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String vscodeVersion = '';

  @override
  void initState() {
    super.initState();

    _getVSCodeVersion();
  }

  Future<void> _getVSCodeVersion() async {
    final shell = Shell();

    try {
      // Run the command to get VS Code version
      var result = await shell.run('code --version');

      // The first line of the output is the version number
      var version = result.outText.split('\n').first;

      // Update the state to display the version
      setState(() {
        vscodeVersion = version;
      });
    } catch (e) {
      setState(() {
        vscodeVersion = 'VS Code not found or error occurred.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: Row(
        children: <Widget>[
          Flexible(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Image.asset(
                  'assets/vscode_icon.png',
                  width: 130,
                  height: 130,
                ),
                const Text(
                  "VS Code",
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
                Text(
                  'Version $vscodeVersion',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(
                  height: 30,
                ),
                GeneralizedButton(
                  icon: Icons.create_new_folder_outlined,
                  title: "Create New Project...",
                  onPressed: () => null,
                ),
                GeneralizedButton(
                  icon: Icons.file_download_outlined,
                  title: "Clone Git Repository...",
                  onPressed: () => null,
                ),
                GeneralizedButton(
                  icon: Icons.folder_copy_outlined,
                  title: "Open Existing Project...",
                  onPressed: () => _openProject(),
                ),
              ],
            ),
          ),
          const Flexible(
            flex: 2,
            child: ProjectListScreen(),
          ),
        ],
      ),
    );
  }
}

Future<List<Map<String, String>>> loadRecentProjects() async {
  List<Map<String, String>> recentProjects = [];

  // Initialize sqflite for FFI usage
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;

  // Locate the VS Code state.vscdb file
  final directory = await getApplicationSupportDirectory();
  final vsCodeDbPath = path.join(
    directory.parent.path,
    'Code/User/globalStorage/state.vscdb',
  );

  if (File(vsCodeDbPath).existsSync()) {
    // Open the database
    final database = await databaseFactory.openDatabase(vsCodeDbPath);

    // Query the recently opened folders
    final result = await database.rawQuery(
        "SELECT value FROM ItemTable WHERE key LIKE 'history.recentlyOpenedPathsList%' LIMIT 10");

    final recentFolders = result
        .map((row) {
          final jsonString = row['value'] as String;
          final parsedJson = jsonDecode(jsonString);
          final entries = parsedJson['entries'] as List<dynamic>;

          // Extract folderUri or fileUri
          return entries
              .map((entry) => entry['folderUri'] ?? entry['fileUri'])
              .cast<String>()
              .take(10) // Limit to first 10 paths
              .toList();
        })
        .expand((folderList) => folderList)
        .toList();

    // Determine the project type and corresponding icon for each folder
    for (String folder in recentFolders) {
      String decodedPath = Uri.parse(folder).toFilePath();
      final iconpath = await ProjectIdentifier.identifyProjectType(decodedPath);
      //final iconPath = ProjectIdentifier.get(projectType);
      recentProjects.add({
        'path': folder,
        'icon': iconpath,
      });
    }

    // Close the database
    await database.close();
    return recentProjects;
  } else {
    return [];
  }
}

void _openProject() async {
  // Open the folder picker dialog
  final String? selectedDirectory = await getDirectoryPath(
    initialDirectory: '/Documents',
    confirmButtonText: 'Select',
  );

  if (selectedDirectory != null) {
    try {
      String decodedPath = Uri.parse(selectedDirectory).toFilePath();

      // Run the shell command with the decoded path
      Shell().run(
          'code "${decodedPath.replaceAll('"', '\\"')}" --new-window --no-sandbox');
      print(
          'Opened project directory: $selectedDirectory in a new VS Code window.');
    } catch (e) {
      print('Error opening directory in VS Code: $e');
    }
  } else {
    // User canceled the picker
    print('No directory selected.');
  }
}

class GeneralizedButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onPressed;

  const GeneralizedButton({
    super.key,
    required this.icon,
    required this.title,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5.0, horizontal: 50.0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: const Color.fromARGB(10, 255, 255, 255),
      ),
      child: Material(
        type: MaterialType.transparency,
        color: Colors.transparent,
        child: InkWell(
          splashColor: Colors.blue.withAlpha(155),
          highlightColor: Colors.transparent,
          onTap: () => onPressed(),
          child: Container(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: <Widget>[
                Icon(
                  icon,
                  size: 18.0,
                  color: Colors.white60,
                ),
                const SizedBox(
                  width: 10.0,
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.0,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  @override
  _ProjectListScreenState createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  late Future<List<Map<String, String>>> _projects;

  @override
  void initState() {
    super.initState();
    _projects = loadRecentProjects();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withAlpha(10),
      child: FutureBuilder<List<Map<String, String>>>(
          future: _projects,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text('Error loading projects'));
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Center(child: Text('No recent projects'));
            } else {
              final projects = snapshot.data!;
              return ListView.builder(
                itemCount: projects.length,
                itemBuilder: (context, index) {
                  final projectPath = projects[index];
                  String decodedPath =
                      Uri.parse(projectPath['path']!).toFilePath();

                  return Container(
                      margin: const EdgeInsets.symmetric(
                          vertical: 5.0, horizontal: 5.0),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: const Color.fromARGB(0, 255, 255, 255),
                      ),
                      child: Material(
                          type: MaterialType.transparency,
                          color: Colors.transparent,
                          child: InkWell(
                              splashColor: Colors.blue.withAlpha(155),
                              highlightColor: Colors.transparent,
                              hoverColor: Colors.white10,
                              focusColor: Colors.white10,
                              onTap: () => Shell().run(
                                  'code "${decodedPath.replaceAll('"', '\\"')}" --new-window --no-sandbox'),
                              child: ListTile(
                                minLeadingWidth: 0,
                                minVerticalPadding: 10,
                                contentPadding: const EdgeInsets.only(left: 10),
                                leading: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Image.asset(
                                        "assets/blank_document.png",
                                        height: 36,
                                      ),
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 5.0),
                                        child: SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: SvgPicture.asset(
                                            projectPath['icon']!,
                                            //width: 15,
                                            //height: 18,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ]),
                                title: Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Text(
                                    _getPrettyName(decodedPath),
                                    style: TextStyle(
                                        fontSize: 14, color: Colors.grey[100]),
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Text(
                                    _trimPath(decodedPath),
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                  ),
                                ),
                              ))));
                },
              );
            }
          }),
    );
  }
}

String _trimPath(String fullPath) {
  const int maxLength = 27; // Maximum characters to display

  // Decode the URI format to get the actual file path
  String decodedPath = Uri.decodeFull(fullPath);

  // Extract the last part of the path if it exceeds maxLength
  if (decodedPath.length > maxLength) {
    return '...${decodedPath.substring(decodedPath.length - maxLength)}';
  } else {
    return decodedPath;
  }
}

String _getPrettyName(String fullPath) {
  // Decode the URI to get the actual path
  String decodedPath = Uri.decodeFull(fullPath);

  // Extract the directory or file name from the path
  String directoryName = decodedPath.split('/').last;

  // Replace non-alphanumeric characters with a space
  directoryName = directoryName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), ' ');

  // Convert to title case
  directoryName = directoryName
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
      .join(' ');

  return directoryName;
}

class ProjectIdentifier {
  static Future<String> identifyProjectType(String path) async {
    final directory = Directory(path);

    // Check for characteristic files/folders for each project type
    if (await File('${directory.path}/pubspec.yaml').exists()) {
      return 'assets/icons/flutter.svg';
    } else if (await File('${directory.path}/package.json').exists()) {
      return 'assets/icons/nodejs.svg';
    } else if (await File('${directory.path}/requirements.txt').exists() ||
        await File('${directory.path}/setup.py').exists()) {
      return 'assets/icons/python.svg';
    } else if (await Directory('${directory.path}/Assets').exists()) {
      return 'assets/icons/unity.svg';
    } else if (await File('${directory.path}/*.csproj').exists()) {
      return 'assets/icons/net.svg';
    } else if (await File('${directory.path}/index.html').exists()) {
      return 'assets/icons/html.svg';
    } else if (await File('${directory.path}/Cargo.toml').exists()) {
      return 'assets/icons/rust.svg';
    } else if (await File('${directory.path}/pom.xml').exists()) {
      return 'assets/icons/java.svg';
    } else if (await File('${directory.path}/build.gradle').exists()) {
      return 'assets/icons/gradle.svg';
    }

    return 'assets/icons/flutter.svg';
  }
}
