#!/usr/bin/env python3
"""Exercise the production plist transformations without changing host services."""
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "Umbra/RHServicePorts.m").read_text()
parsers = source[source.index("static NSNumber *PortNumber("):source.index("static NSMutableDictionary *ReadConfig(")]
check = r'''
int main(void) {
    @autoreleasepool {
        for (id value in @[@"", @"0", @"65536", @"-1", @"22abc", @"１２", @"1.5", @{}]) {
            assert(PortNumber(value) == nil);
        }
        assert([PortNumber(@"65535") isEqual:@65535]);
        assert([PortNumber(@1) isEqual:@1]);
        NSMutableDictionary *ssh = [@{
            @"ProgramArguments": @[@"/bin/sh", @"/usr/libexec/sshd-keygen-wrapper", @"-i"],
            @"Sockets": @{
                @"SSHListener": @{@"SockServiceName": @"ssh", @"SockNodeName": @"127.0.0.1"},
                @"SSHListener2": @{@"SockServiceName": @"2222", @"SockFamily": @"IPv4"}
            },
            @"SessionCreate": @YES
        } mutableCopy];
        assert(([ConfigPorts(ssh, @"openssh", nil) isEqual:@[@22, @2222]]));
        assert(ConfigPorts(ssh, @"openssh", @[@2022, @2223]));
        assert(([ConfigPorts(ssh, @"openssh", nil) isEqual:@[@2022, @2223]]));
        assert([ssh[@"Sockets"][@"SSHListener"][@"SockNodeName"] isEqual:@"127.0.0.1"]);
        assert([ssh[@"Sockets"][@"SSHListener2"][@"SockFamily"] isEqual:@"IPv4"]);
        assert([ssh[@"SessionCreate"] boolValue]);
        assert(ConfigPorts(ssh, @"openssh", @[@22]));
        assert(ssh[@"Sockets"][@"SSHListener2"] == nil);
        assert(([ConfigPorts(ssh, @"openssh", nil) isEqual:@[@22]]));
        assert(!ConfigPorts(ssh, @"openssh", @[]));
        ssh[@"ProgramArguments"] = @[@"sshd"];
        assert(!ConfigPorts(ssh, @"openssh", nil));

        NSMutableDictionary *dropbear = [@{
            @"ProgramArguments": @[@"/bin/sh", @"/usr/libexec/dropbear-wrapper", @"[::1]:44"]
        } mutableCopy];
        assert(([ConfigPorts(dropbear, @"dropbear", @[@4444]) isEqual:@[@44]]));
        assert([dropbear[@"ProgramArguments"] lastObject] &&
               [[dropbear[@"ProgramArguments"] lastObject] isEqual:@"[::1]:4444"]);
        assert(!ConfigPorts(dropbear, @"dropbear", @[@44, @45]));

        NSMutableDictionary *frida = [@{
            @"ProgramArguments": @[@"/bin/sh", @"/usr/sbin/frida-server-wrapper", @"--token", @"preserve-me"]
        } mutableCopy];
        assert(([ConfigPorts(frida, @"frida", @[@37042]) isEqual:@[@27042]]));
        assert(([frida[@"ProgramArguments"] isEqual:@[@"/bin/sh", @"/usr/sbin/frida-server-wrapper",
            @"--token", @"preserve-me", @"--listen", @"127.0.0.1:37042"]]));
        frida[@"ProgramArguments"] = @[@"frida-server", @"--listen=[::1]:27042"];
        assert(ConfigPorts(frida, @"frida", @[@37042]));
        assert([[frida[@"ProgramArguments"] lastObject] isEqual:@"--listen=[::1]:37042"]);
        frida[@"ProgramArguments"] = @[@"frida-server", @"-l", @"127.0.0.1:27042", @"--listen=127.0.0.1:27043"];
        assert(!ConfigPorts(frida, @"frida", nil));
        frida[@"ProgramArguments"] = @[@"frida-server", @"-l"];
        assert(!ConfigPorts(frida, @"frida", nil));
        assert(!ConfigPorts(frida, @"unknown", nil));
        puts("Service ports: bounds, listener removal, addresses and unrelated arguments passed.");
    }
}
'''
with tempfile.TemporaryDirectory(prefix="umbra-ports-") as directory:
    temp = Path(directory)
    path = temp / "check.m"
    path.write_text('#import <Foundation/Foundation.h>\n#include <assert.h>\n' + parsers + check)
    executable = temp / "check"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-framework", "Foundation", str(path), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
