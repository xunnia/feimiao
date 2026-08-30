import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/system_network_proxy.dart';

void main() {
  test('system proxy keeps loopback OAuth callback direct', () {
    expect(
      SystemNetworkProxy.findProxyForTest(
        Uri.parse('http://localhost:1455/auth/callback'),
        host: '10.0.0.2',
        port: 7890,
      ),
      'DIRECT',
    );
    expect(
      SystemNetworkProxy.findProxyForTest(
        Uri.parse('http://127.0.0.1:1457/auth/callback'),
        host: '10.0.0.2',
        port: 7890,
      ),
      'DIRECT',
    );
  });

  test('system proxy routes external hosts and honors exclusions', () {
    expect(
      SystemNetworkProxy.findProxyForTest(
        Uri.parse('https://auth.openai.com/oauth/token'),
        host: '10.0.0.2',
        port: 7890,
      ),
      'PROXY 10.0.0.2:7890',
    );
    expect(
      SystemNetworkProxy.findProxyForTest(
        Uri.parse('https://api.example.com/v1/models'),
        host: '10.0.0.2',
        port: 7890,
        exclusions: ['*.example.com'],
      ),
      'DIRECT',
    );
    expect(
      SystemNetworkProxy.findProxyForTest(
        Uri.parse('https://auth.openai.com/oauth/token'),
        host: '2001:db8::2',
        port: 7890,
      ),
      'PROXY [2001:db8::2]:7890',
    );
  });

  test('missing system proxy falls back to direct sockets', () {
    expect(
      SystemNetworkProxy.findProxyForTest(
        Uri.parse('https://auth.openai.com/oauth/token'),
        host: '',
        port: 0,
      ),
      'DIRECT',
    );
  });

  test('PAC route can select a proxy per external host', () {
    expect(
      SystemNetworkProxy.findProxyForTest(
        Uri.parse('https://auth.openai.com/oauth/token'),
        host: '',
        port: 0,
        routes: const {
          'auth.openai.com': {'host': '10.0.0.4', 'port': 7890},
        },
      ),
      'PROXY 10.0.0.4:7890',
    );
    expect(
      SystemNetworkProxy.findProxyForTest(
        Uri.parse('https://chatgpt.com/backend-api/codex/models'),
        host: '',
        port: 0,
        routes: const {
          'chatgpt.com': {'host': '2001:db8::4', 'port': 1080, 'type': 'socks'},
        },
      ),
      'SOCKS [2001:db8::4]:1080',
    );
    expect(
      SystemNetworkProxy.findProxyForTest(
        Uri.parse('https://api.example.com/v1/models'),
        host: '',
        port: 0,
        routes: const {
          '*.example.com': {'host': '10.0.0.4', 'port': 7890},
        },
      ),
      'PROXY 10.0.0.4:7890',
    );
    expect(
      SystemNetworkProxy.findProxyForTest(
        Uri.parse('https://auth.openai.com/oauth/token'),
        host: '10.0.0.4',
        port: 7890,
        routes: const {
          'auth.openai.com': {'type': 'direct'},
        },
      ),
      'DIRECT',
    );
  });
}
