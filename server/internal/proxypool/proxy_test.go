package proxypool

import "testing"

func TestParseExtractsPublicAddresses(t *testing.T) {
	raw := `
	更好用的代理ip请访问：www.qiyunip.com
	1.2.3.4:8080
	5.6.7.8:3128  10.0.0.1:8888
	127.0.0.1:8080
	not-an-ip:80
	9.9.9.9:70000
	`
	proxies := Parse(raw)
	if len(proxies) != 2 {
		t.Fatalf("expected 2 proxies, got %d: %+v", len(proxies), proxies)
	}
	if proxies[0].Address() != "1.2.3.4:8080" {
		t.Fatalf("unexpected first proxy %s", proxies[0].Address())
	}
	if proxies[1].Address() != "5.6.7.8:3128" {
		t.Fatalf("unexpected second proxy %s", proxies[1].Address())
	}
}

func TestParseJSONList(t *testing.T) {
	raw := []byte(`{"code":0,"data":{"proxies":["8.8.4.4:443","1.1.1.1:8443"]}}`)
	proxies, err := ParseJSONList(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(proxies) != 2 {
		t.Fatalf("expected 2 proxies, got %d", len(proxies))
	}
	if proxies[0].String() != "http://8.8.4.4:443" {
		t.Fatalf("unexpected proxy string %s", proxies[0].String())
	}
}

func TestParseJSONListRejectsGarbage(t *testing.T) {
	if _, err := ParseJSONList([]byte("<html>")); err == nil {
		t.Fatal("expected an error for a non-JSON payload")
	}
	if _, err := ParseJSONList(nil); err == nil {
		t.Fatal("expected an error for an empty payload")
	}
}

func TestProxyValidRejectsLocalAddresses(t *testing.T) {
	cases := []struct {
		proxy Proxy
		want  bool
	}{
		{Proxy{Host: "1.2.3.4", Port: 8080}, true},
		{Proxy{Host: "10.1.2.3", Port: 8080}, false},
		{Proxy{Host: "192.168.1.10", Port: 8080}, false},
		{Proxy{Host: "127.0.0.1", Port: 8080}, false},
		{Proxy{Host: "1.2.3.4", Port: 0}, false},
		{Proxy{Host: "example.com", Port: 80}, false},
	}
	for _, testCase := range cases {
		if got := testCase.proxy.Valid(); got != testCase.want {
			t.Fatalf("Valid(%s) = %v, want %v", testCase.proxy.Address(), got, testCase.want)
		}
	}
}
