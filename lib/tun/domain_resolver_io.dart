import 'dart:async';
import 'dart:convert';
import 'dart:io';

abstract interface class DomainResolver {
  Future<String?> reverseLookup(String ip);
}

class DefaultDomainResolver implements DomainResolver {
  const DefaultDomainResolver({
    this.systemTimeout = const Duration(milliseconds: 800),
    this.dohTimeout = const Duration(milliseconds: 900),
  });

  final Duration systemTimeout;
  final Duration dohTimeout;

  static const _dohTemplates = [
    'https://dns.google/resolve?name={ptr}&type=PTR',
    'https://dns.alidns.com/resolve?name={ptr}&type=PTR',
    'https://doh.pub/resolve?name={ptr}&type=PTR',
    'https://cloudflare-dns.com/dns-query?name={ptr}&type=PTR',
  ];

  @override
  Future<String?> reverseLookup(String ip) async {
    final parsed = InternetAddress.tryParse(ip);
    if (parsed == null) {
      return null;
    }

    final systemName = await _systemReverse(parsed);
    if (systemName != null) {
      return systemName;
    }

    final ptr = _ipv4PtrName(ip);
    if (ptr == null) {
      return null;
    }
    for (final template in _dohTemplates) {
      final name = await _dohReverse(template.replaceFirst('{ptr}', ptr));
      if (name != null) {
        return name;
      }
    }
    return null;
  }

  Future<String?> _systemReverse(InternetAddress address) async {
    try {
      final resolved = await address.reverse().timeout(systemTimeout);
      return _normalizeDomain(resolved.host);
    } on Object {
      return null;
    }
  }

  Future<String?> _dohReverse(String url) async {
    final client = HttpClient()..connectionTimeout = dohTimeout;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(dohTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
      final response = await request.close().timeout(dohTimeout);
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }
      final body = await utf8.decoder.bind(response).join().timeout(dohTimeout);
      final json = jsonDecode(body);
      if (json is! Map<String, Object?> || json['Status'] != 0) {
        return null;
      }
      final answers = json['Answer'];
      if (answers is! List) {
        return null;
      }
      for (final answer in answers) {
        if (answer is! Map<String, Object?>) {
          continue;
        }
        final data = answer['data']?.toString();
        final name = _normalizeDomain(data);
        if (name != null) {
          return name;
        }
      }
      return null;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  String? _ipv4PtrName(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return null;
    }
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) {
        return null;
      }
    }
    return '${parts.reversed.join('.')}.in-addr.arpa';
  }

  String? _normalizeDomain(String? value) {
    var domain = value?.trim();
    if (domain == null || domain.isEmpty) {
      return null;
    }
    if (domain.endsWith('.')) {
      domain = domain.substring(0, domain.length - 1);
    }
    if (domain.isEmpty || InternetAddress.tryParse(domain) != null) {
      return null;
    }
    return domain;
  }
}
