import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/components/task_list_item.dart';
import 'package:bsat/screens/tasks/edit_task.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../components/dialogs/confirm_dialog.dart';
import '../../utils/constants.dart';

class TaskManagerPage extends StatefulWidget {
  const TaskManagerPage({super.key});

  @override
  State<TaskManagerPage> createState() => _TaskManagerPageState();
}

class _TaskManagerPageState extends State<TaskManagerPage> {
  final _sqliteService = SQLiteService();

  final _searchController = TextEditingController();

  List tasks = [];

  void _getAllTasks() async {
    await _sqliteService.queryAll('tasks').then(
      (value) {
        setState(() {
          tasks = value;
        });
      },
    );
  }

  void _searchTasks(String query) async {
    await _sqliteService.queryCustom('tasks', 'code LIKE ?', ['%$query%']).then(
      (value) {
        setState(() {
          tasks = value;
        });
      },
    );
  }

  Future<void> _deleteSelected(Set selectedId) async {
    for (var id in selectedId) {
      await _sqliteService.deleteStuff(id, 'tasks');
    }

    _getAllTasks();

    // await _sqliteService.deleteWhere('tasks', 'nextTaskDate < ?',
    //     [DateTime.now().millisecondsSinceEpoch]).then((value) {
    //   _getAllTasks();
    // });
  }

  void checkPermission(BuildContext context) async {
    if (!(await Permission.scheduleExactAlarm.isGranted)) {
      await Permission.scheduleExactAlarm.request();
    }
  }

  @override
  void initState() {
    super.initState();
    _getAllTasks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(context, 'Task Scheduler'),
            Padding(
              padding: const EdgeInsets.only(
                left: kPagePadding,
                top: kPagePadding,
                right: kPagePadding,
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search tasks',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(kBorderRadius),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                ),
                onChanged: (value) async {
                  if (value.isEmpty) {
                    _getAllTasks();
                  } else {
                    _searchTasks(value);
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                left: kPagePadding,
                top: kPagePadding,
                right: kPagePadding,
              ),
              child: Row(
                children: [
                  Text("Scheduled tasks (${tasks.length})"),
                ],
              ),
            ),
            tasks.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(kPagePadding),
                    child: Center(
                      child: Text(
                        'No tasks scheduled yet. Click the + button to add a new task.',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return Padding(
                        padding: const EdgeInsets.only(
                          left: kPagePadding,
                          right: kPagePadding,
                          bottom: kPagePadding / 2,
                        ),
                        child: GestureDetector(
                          onTap: () async {
                            await Navigator.of(context)
                                .push(
                              PageRouteBuilder(
                                pageBuilder:
                                    (context, animation, secondaryAnimation) =>
                                        EditTaskPage(taskId: task['id']),
                                transitionsBuilder: (context, animation,
                                    secondaryAnimation, child) {
                                  return CupertinoPageTransition(
                                    primaryRouteAnimation: animation,
                                    secondaryRouteAnimation: secondaryAnimation,
                                    linearTransition: true,
                                    child: child,
                                  );
                                },
                              ),
                            )
                                .then((value) {
                              if (value == true) {
                                _getAllTasks();
                                setState(() {});
                              }
                            });
                          },
                          onLongPress: () {
                            _showDeleteSheet(task['id']);
                          },
                          child: taskListItem(
                            context,
                            task['code'],
                            getNormalDate(DateTime.fromMillisecondsSinceEpoch(
                              task['startDate'],
                            )),
                            getNormalDate(DateTime.fromMillisecondsSinceEpoch(
                              task['startDate'],
                            ).add(Duration(days: task['duration']))),
                            task['id'],
                            _getAllTasks,
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.transparent,
        child: Icon(
          Icons.add,
          color: kPrimaryColor,
        ),
        onPressed: () async {
          await Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  const EditTaskPage(taskId: -1),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                return CupertinoPageTransition(
                  primaryRouteAnimation: animation,
                  secondaryRouteAnimation: secondaryAnimation,
                  linearTransition: true,
                  child: child,
                );
              },
            ),
          );

          _getAllTasks();
        },
      ),
    );
  }

  Future<dynamic> _showDeleteSheet(int selectedId) {
    Set<dynamic> selectedIds = {selectedId};

    return showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
          return Container(
            padding: kPagePaddingInsets,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Delete tasks'),
                      Checkbox(
                        value: selectedIds.length == tasks.length,
                        onChanged: (value) {
                          if (value ?? false) {
                            selectedIds =
                                tasks.map((task) => task['id']).toSet();
                          } else {
                            selectedIds = {};
                          }
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: kPagePadding / 2),
                  Column(
                    children: tasks.map(
                      (task) {
                        return Padding(
                          padding:
                              const EdgeInsets.only(bottom: kPagePadding / 2),
                          child: GestureDetector(
                            onLongPress: () {},
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                taskListItem(
                                  context,
                                  task['code'],
                                  getNormalDate(
                                    DateTime.fromMillisecondsSinceEpoch(
                                      task['startDate'],
                                    ),
                                  ),
                                  getNormalDate(
                                    DateTime.fromMillisecondsSinceEpoch(
                                      task['startDate'],
                                    ).add(
                                      Duration(days: task['duration']),
                                    ),
                                  ),
                                  task['id'],
                                  _getAllTasks,
                                ),
                                Checkbox(
                                  value: selectedIds.contains(task['id']),
                                  onChanged: (value) {
                                    if (value ?? false) {
                                      selectedIds.add(task['id']);
                                    } else {
                                      selectedIds.remove(task['id']);
                                    }
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ).toList(),
                  ),
                  const SizedBox(height: kPagePadding / 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          // showLoadingDialog(context, text: 'Deleting tasks...');
                          // await _deleteSelected(selectedIds);
                          // Navigator.pop(context);
                          // Navigator.pop(context);
                          showConfirmDialog(
                            context,
                            title: 'Delete ${selectedIds.length} Tasks',
                            message:
                                'Are you sure you want to delete the selected tasks?',
                          ).then(
                            (value) async {
                              if (value == true) {
                                showLoadingDialog(context, text: 'Deleting tasks...');
                                await _deleteSelected(selectedIds);
                                Navigator.pop(context);
                                Navigator.pop(context);
                              }
                            },
                          );
                        },
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }
}
