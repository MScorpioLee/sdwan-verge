abstract interface class DomainResolver {
  Future<String?> reverseLookup(String ip);
}

class DefaultDomainResolver implements DomainResolver {
  const DefaultDomainResolver();

  @override
  Future<String?> reverseLookup(String ip) async => null;
}
