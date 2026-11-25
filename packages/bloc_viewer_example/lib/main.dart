import 'dart:async';

import 'package:bloc_viewer/bloc_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void main() {
  // 1) Install BEFORE creating any bloc.
  BlocViewer.install();
  // 2) Optional: makes object states editable from the DevTools tree.
  BlocViewer.registerDecoder<SettingsState>(SettingsState.fromJson);
  BlocViewer.registerDecoder<TodoState>(TodoState.fromJson);
  runApp(const DemoApp());
}

// ------------------------------------------------------------------ cubits

class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);
  void increment() => emit(state + 1);
}

class Profile {
  const Profile({required this.name, required this.age});
  final String name;
  final int age;
  Map<String, dynamic> toJson() => {'name': name, 'age': age};
  factory Profile.fromJson(Map<String, dynamic> j) =>
      Profile(name: j['name'] as String, age: j['age'] as int);
}

class SettingsState {
  const SettingsState({
    this.darkMode = false,
    this.fontScale = 1.0,
    this.username = 'oliver',
    this.tags = const ['a', 'b'],
    this.profile = const Profile(name: 'Oliver', age: 40),
  });
  final bool darkMode;
  final double fontScale;
  final String username;
  final List<String> tags;
  final Profile profile;

  SettingsState copyWith({bool? darkMode, double? fontScale, List<String>? tags}) =>
      SettingsState(
        darkMode: darkMode ?? this.darkMode,
        fontScale: fontScale ?? this.fontScale,
        username: username,
        tags: tags ?? this.tags,
        profile: profile,
      );

  Map<String, dynamic> toJson() => {
        'darkMode': darkMode,
        'fontScale': fontScale,
        'username': username,
        'tags': tags,
        'profile': profile.toJson(),
      };

  factory SettingsState.fromJson(Map<String, dynamic> j) => SettingsState(
        darkMode: j['darkMode'] as bool,
        fontScale: (j['fontScale'] as num).toDouble(),
        username: j['username'] as String,
        tags: (j['tags'] as List).cast<String>(),
        profile: Profile.fromJson((j['profile'] as Map).cast<String, dynamic>()),
      );
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit() : super(const SettingsState());
  void toggleDark() => emit(state.copyWith(darkMode: !state.darkMode));
  void addTag() => emit(state.copyWith(tags: [...state.tags, 'tag${state.tags.length}']));
  void removeTag() {
    if (state.tags.isNotEmpty) emit(state.copyWith(tags: state.tags.sublist(0, state.tags.length - 1)));
  }
}

// -------------------------------------------------------------------- bloc

class Todo {
  const Todo(this.title, this.done);
  final String title;
  final bool done;
  Map<String, dynamic> toJson() => {'title': title, 'done': done};
  factory Todo.fromJson(Map<String, dynamic> j) => Todo(j['title'] as String, j['done'] as bool);
}

class TodoState {
  const TodoState(this.items);
  final List<Todo> items;
  Map<String, dynamic> toJson() => {'items': items.map((e) => e.toJson()).toList()};
  factory TodoState.fromJson(Map<String, dynamic> j) => TodoState(
      (j['items'] as List).map((e) => Todo.fromJson((e as Map).cast<String, dynamic>())).toList());
}

sealed class TodoEvent {}

class AddTodo extends TodoEvent {}

class ToggleFirst extends TodoEvent {}

class TodoBloc extends Bloc<TodoEvent, TodoState> {
  TodoBloc() : super(const TodoState([Todo('Try the Bloc Viewer', false)])) {
    on<AddTodo>((e, emit) =>
        emit(TodoState([...state.items, Todo('Todo #${state.items.length + 1}', false)])));
    on<ToggleFirst>((e, emit) {
      if (state.items.isEmpty) return;
      final first = state.items.first;
      emit(TodoState([Todo(first.title, !first.done), ...state.items.skip(1)]));
    });
  }
}

// ------------------------------------------------- dynamic, self-ticking one

class TimerCubit extends Cubit<int> {
  TimerCubit() : super(0) {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => emit(state + 1));
  }
  late final Timer _timer;
  @override
  Future<void> close() {
    _timer.cancel();
    return super.close();
  }
}

// ---------------------------------------------------------------------- UI

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => CounterCubit(), lazy: false),
        BlocProvider(create: (_) => SettingsCubit(), lazy: false),
        BlocProvider(create: (_) => TodoBloc(), lazy: false),
      ],
      child: const MaterialApp(home: DemoPage()),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final List<int> _timers = [];
  int _nextTimer = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bloc Viewer demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(
              onPressed: () => context.read<CounterCubit>().increment(),
              child: BlocBuilder<CounterCubit, int>(builder: (_, s) => Text('Counter: $s')),
            ),
            OutlinedButton(
                onPressed: () => context.read<SettingsCubit>().toggleDark(),
                child: const Text('Toggle dark')),
            OutlinedButton(
                onPressed: () => context.read<SettingsCubit>().addTag(), child: const Text('Add tag')),
            OutlinedButton(
                onPressed: () => context.read<SettingsCubit>().removeTag(),
                child: const Text('Remove tag')),
            OutlinedButton(
                onPressed: () => context.read<TodoBloc>().add(AddTodo()), child: const Text('Add todo')),
            OutlinedButton(
                onPressed: () => context.read<TodoBloc>().add(ToggleFirst()),
                child: const Text('Toggle first todo')),
          ]),
          const Divider(height: 32),
          Row(children: [
            FilledButton.tonal(
                onPressed: () => setState(() => _timers.add(_nextTimer++)),
                child: const Text('Add timer cubit')),
            const SizedBox(width: 8),
            OutlinedButton(
                onPressed: _timers.isEmpty ? null : () => setState(_timers.removeLast),
                child: const Text('Dispose last timer')),
          ]),
          for (final id in _timers)
            BlocProvider(
              key: ValueKey(id),
              create: (_) => TimerCubit(),
              child: BlocBuilder<TimerCubit, int>(
                builder: (_, s) => ListTile(title: Text('Timer $id: $s s')),
              ),
            ),
        ],
      ),
    );
  }
}
