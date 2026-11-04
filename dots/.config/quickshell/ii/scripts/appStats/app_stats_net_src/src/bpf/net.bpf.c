// SPDX-License-Identifier: GPL-2.0
//
// Per-socket network bytes, and the process each socket belongs to.
//
// Two halves, joined by the socket cookie (a per-boot unique id the kernel gives
// every socket, and the same one `ss` and NETLINK_SOCK_DIAG report):
//
//   - cgroup_skb ingress/egress, attached to the root cgroup, see every IP packet a
//     socket sends or receives — TCP and UDP alike, so QUIC is counted — and add its
//     length to that socket's counters. Packets that belong to no socket (ARP, DHCP,
//     ICMP replies, forwarding) never reach these hooks; they are what the
//     interfaces count beyond the sum of the sockets.
//
//   - fentry on the TCP and UDP sendmsg/recvmsg entry points run in the context of
//     the process doing the I/O, which is where the owner can be read: its tgid, its
//     parent's tgid and its name. Recorded once per socket. The parent is what lets
//     a process that exited before user space looked (a half-second curl) still be
//     credited to the app that ran it.
//
// Packets counted before a socket is tagged stay on its cookie until it is; nothing
// is lost to the order the two halves run in.

#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_endian.h>

char LICENSE[] SEC("license") = "GPL";

#define AF_INET 2
#define AF_INET6 10
#define IPPROTO_TCP 6

// Header bytes of one IP packet, for the segments of a coalesced buffer: IPv4 20 /
// IPv6 40, plus TCP with the timestamp option (32) or UDP (8).
#define TCP_HDR 32
#define UDP_HDR 8

// Only the two fields read here; CO-RE resolves them against the running kernel's
// BTF by name, so no vmlinux.h is needed.
struct task_struct {
    struct task_struct *real_parent;
    struct task_struct *group_leader;
    int tgid;
    char comm[16];
} __attribute__((preserve_access_index));

struct sock;

struct counts {
    __u64 rx;
    __u64 tx;
};

struct owner {
    __u32 tgid;
    __u32 ppid;
    char comm[16];
};

struct {
    __uint(type, BPF_MAP_TYPE_LRU_HASH);
    __uint(max_entries, 65536);
    __type(key, __u64);
    __type(value, struct counts);
} bytes SEC(".maps");

struct {
    __uint(type, BPF_MAP_TYPE_LRU_HASH);
    __uint(max_entries, 65536);
    __type(key, __u64);
    __type(value, struct owner);
} owners SEC(".maps");

// A connection to this machine itself is not network use.
static __always_inline int is_loopback(struct __sk_buff *skb)
{
    if (skb->family == AF_INET)
        return (bpf_ntohl(skb->remote_ip4) >> 24) == 127;
    if (skb->family == AF_INET6) {
        __u32 a0 = skb->remote_ip6[0], a1 = skb->remote_ip6[1];
        __u32 a2 = skb->remote_ip6[2], a3 = skb->remote_ip6[3];
        if (a0 == 0 && a1 == 0 && a2 == 0 && a3 == bpf_htonl(1))
            return 1;
        if (a0 == 0 && a1 == 0 && a2 == bpf_htonl(0xffff))
            return (bpf_ntohl(a3) >> 24) == 127;
    }
    return 0;
}

// Bytes on the wire at IP level. GRO on receive and GSO/TSO on send hand this hook one
// buffer for many packets, carrying a single header; each of the other packets had its
// own on the wire, and the interfaces count them. Adding them back is what makes the
// per-app figures add up to what the network cards carried.
static __always_inline __u64 wire_len(struct __sk_buff *skb)
{
    __u64 len = skb->len;
    __u32 segs = skb->gso_segs;
    if (segs <= 1)
        return len;
    __u32 hdr = skb->family == AF_INET6 ? 40 : 20;
    // skb->sk is only a sock_common to the verifier; the protocol needs the full socket.
    struct bpf_sock *sk = skb->sk;
    if (sk)
        sk = bpf_sk_fullsock(sk);
    hdr += (sk && sk->protocol == IPPROTO_TCP) ? TCP_HDR : UDP_HDR;
    return len + (__u64)(segs - 1) * hdr;
}

static __always_inline void count(struct __sk_buff *skb, int egress)
{
    if (is_loopback(skb))
        return;
    __u64 cookie = bpf_get_socket_cookie(skb);
    if (!cookie)
        return;
    __u64 len = wire_len(skb);
    struct counts *c = bpf_map_lookup_elem(&bytes, &cookie);
    if (!c) {
        struct counts zero = {};
        bpf_map_update_elem(&bytes, &cookie, &zero, BPF_NOEXIST);
        c = bpf_map_lookup_elem(&bytes, &cookie);
        if (!c)
            return;
    }
    if (egress)
        __sync_fetch_and_add(&c->tx, len);
    else
        __sync_fetch_and_add(&c->rx, len);
}

SEC("cgroup_skb/ingress")
int count_ingress(struct __sk_buff *skb)
{
    count(skb, 0);
    return 1;
}

SEC("cgroup_skb/egress")
int count_egress(struct __sk_buff *skb)
{
    count(skb, 1);
    return 1;
}

static __always_inline void tag(struct sock *sk)
{
    __u64 cookie = bpf_get_socket_cookie(sk);
    if (!cookie || bpf_map_lookup_elem(&owners, &cookie))
        return;
    struct owner o = {};
    o.tgid = bpf_get_current_pid_tgid() >> 32;
    struct task_struct *task = (struct task_struct *)bpf_get_current_task();
    o.ppid = BPF_CORE_READ(task, real_parent, tgid);
    // The process's name, not the thread's: a browser's network thread is called
    // "Socket Thread", and that is not what a row should be named after.
    BPF_CORE_READ_STR_INTO(&o.comm, task, group_leader, comm);
    bpf_map_update_elem(&owners, &cookie, &o, BPF_NOEXIST);
}

SEC("fentry/tcp_sendmsg")
int BPF_PROG(tag_tcp_send, struct sock *sk)
{
    tag(sk);
    return 0;
}

SEC("fentry/tcp_recvmsg")
int BPF_PROG(tag_tcp_recv, struct sock *sk)
{
    tag(sk);
    return 0;
}

SEC("fentry/udp_sendmsg")
int BPF_PROG(tag_udp_send, struct sock *sk)
{
    tag(sk);
    return 0;
}

SEC("fentry/udp_recvmsg")
int BPF_PROG(tag_udp_recv, struct sock *sk)
{
    tag(sk);
    return 0;
}

SEC("fentry/udpv6_sendmsg")
int BPF_PROG(tag_udp6_send, struct sock *sk)
{
    tag(sk);
    return 0;
}

SEC("fentry/udpv6_recvmsg")
int BPF_PROG(tag_udp6_recv, struct sock *sk)
{
    tag(sk);
    return 0;
}
