/// Decode the SQLite membership projection without depending on a database.
Set<int> parseTransactionBookIds(Object? value) => value == null
    ? <int>{}
    : value.toString().split(',').map(int.tryParse).whereType<int>().toSet();
