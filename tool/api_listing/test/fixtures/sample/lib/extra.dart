export 'src/impl.dart' show Mode;

class Extra {
  Extra.named();

  static const int limit = 3;

  set value(int value) {}
}

abstract interface class Port {
  int get size;

  set size(int value);

  void close();
}
