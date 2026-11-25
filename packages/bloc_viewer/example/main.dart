import 'package:bloc/bloc.dart';
import 'package:bloc_viewer/bloc_viewer.dart';

class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);

  void increment() => emit(state + 1);
}

void main() {
  BlocViewer.install();
  final cubit = CounterCubit()..increment();
  print(cubit.state);
}
