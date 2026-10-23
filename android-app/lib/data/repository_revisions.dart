/// Separate change domains so chatting/configuration does not replay finances.
enum RepositoryChange { financial, chat, settings, ai }

class RepositoryRevisions {
  int total = 0;
  final Map<RepositoryChange, int> _domains = {};
  int of(RepositoryChange domain) => _domains[domain] ?? 0;
  void advance(RepositoryChange domain) {
    total++;
    _domains[domain] = of(domain) + 1;
  }
}
