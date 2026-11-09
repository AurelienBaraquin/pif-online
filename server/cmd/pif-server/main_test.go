package main

import (
	"net"
	"reflect"
	"testing"
)

func TestJoinAddressesKeepsPrivateIPv4Only(t *testing.T) {
	interfaces := []net.Addr{
		&net.IPNet{IP: net.IPv4(127, 0, 0, 1)},
		&net.IPNet{IP: net.IPv4(192, 168, 1, 20)},
		&net.IPNet{IP: net.IPv4(8, 8, 8, 8)},
		&net.IPNet{IP: net.ParseIP("fd00::1")},
		&net.TCPAddr{IP: net.IPv4(10, 0, 0, 1)},
	}

	got := joinAddresses(interfaces, 7777)

	if want := []string{"192.168.1.20:7777"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("joinAddresses = %v, want %v", got, want)
	}
}
