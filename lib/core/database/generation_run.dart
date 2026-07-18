enum GenerationRunState {
  preparing('preparing'),
  requesting('requesting'),
  streaming('streaming'),
  waitingTool('waiting_tool'),
  completed('completed'),
  failed('failed'),
  cancelled('cancelled'),
  interrupted('interrupted');

  const GenerationRunState(this.databaseValue);

  final String databaseValue;

  bool get isTerminal => switch (this) {
    completed || failed || cancelled || interrupted => true,
    preparing || requesting || streaming || waitingTool => false,
  };
}
