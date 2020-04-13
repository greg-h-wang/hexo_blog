---
title: RabbitMQ 集群架构搭建与高可用性实现
date: 2020-02-24 21:05:05
tags: rabbitmq
---



> 当你的 RabbitMQ 服务器遇到诸如内存崩溃或者断电等极端情况时，单节点是不能应对这些故障的。因此需要多节点集群部署来弹性应对故障。另外可以通过多节点部署，来扩展消息通信的吞吐量。

<!-- more -->


### [](#1-集群搭建 "1. 集群搭建")1. 集群搭建

首先，我们不用关心 RabbitMQ 的集群策略、节点类型等问题，可以先手动把 RabbitMQ 的集群搭建好，再一步步地了解其原理。

#### [](#1-1-准备两个节点 "1.1 准备两个节点")1.1 准备两个节点

搭建的详细过程就不再叙述，具体可参考 [RabbitMQ 安装](http://note.youdao.com/noteshare?id=ccf5bf5eb8cea8ada9ba76d51d401be6)。

我在两台机器上分别安装了 RabbitMQ，在 / etc/hostname 里也分别配置了机器名：nc060、nc078，要保证两台机器互相能 ping 通。

#### [](#1-2-共享Erlang-Cookie "1.2 共享Erlang Cookie")1.2 共享 Erlang Cookie

erlang.cookie 是 erlang 实现分布式通信的必要文件，erlang 之间的共享通信要求分布式的每个节点上要保持相同的 erlang.cookie 文件，同时保证文件的权限是 400。因此，先把两台 RabbitMQ 服务关闭，其次，我们把 nc060 和 nc078 的 erlang.cookie 设置成相同，我是把 nc060 上的 erlang.cookie 内容复制到 nc078 机器下。

如果我们使用解压缩方式安装部署的 RabbitMQ，那么这个文件会在 $home/.erlang.cookie 下。
如果我们使用 rpm 或者 yum 等安装包方式进行安装的，那么这个文件会在 / var/lib/rabbitmq/.erlang.cookie 下。

放心，到了这里很多人会懵，不要怕，我们已经完成了 RabbitMQ 集群部署的最难的部分了。

#### [](#1-3-部署集群 "1.3 部署集群")1.3 部署集群

此时应保证两台装有 RabbitMQ 的机器具有相同的 erlang.cookie 内容。

进入到 nc060 机器的 RabbitMQ 的 sbin 目录：

```
./rabbitmqctl join_cluster --ram rabbit@nc078
```

此时就加入到 nc078 机器下的集群了，并设置 nc060 为 ram 节点，至于什么是 ram 节点，可参考 2.2 节的内容。

分别启动两台机器的 RabbitMQ 节点：

```
./rabbitmqctl start_app
```

或者

```
./rabbitmq-server -detached
```

此时去 RabbitMQ 的 web 管理页面，会看到已经成功了：

[![](https://static.zhaoyh.com.cn/1531902620506.jpg)](https://static.zhaoyh.com.cn/1531902620506.jpg)

### [](#2-相关说明 "2. 相关说明")2. 相关说明

接下来会对集群部署策略，和一些关键技术做一些介绍。

#### [](#2-1-节点类型 "2.1 节点类型")2.1 节点类型

*   ram（内存）节点：将队列、交换机、绑定等数据存储在内存中，好处是存储和交换机生命之类的操作速度快，坏处是断电后数据会丢失。
*   disk（磁盘）节点：将元数据存储在磁盘中，单节点的 RabbitMQ 只允许磁盘节点，防止重启 RabbitMQ 的时候，丢失配置信息。

> RabbitMQ 要求在集群中至少有一个磁盘节点，所有其他节点可以是内存节点，当节点加入或者离开集群时，必须要将该变更通知到至少一个磁盘节点。如果集群中唯一的一个磁盘节点崩溃的话，集群可以继续路由消息，但是无法进行其他操作（增删改查队列、交换机、权限等），直到节点恢复。

#### [](#2-2-元数据 "2.2 元数据")2.2 元数据

RabbitMQ 会始终记录以下四种类型的内部元数据：

*   队列元数据：队列名称及属性（是否持久化、自动删除等）。
*   交换机元数据：交换机名称、属性、类型等。
*   绑定元数据：将消息路由到队列。
*   vhost 元数据：命名空间属性。

#### [](#2-3-集群模式 "2.3 集群模式")2.3 集群模式

*   普通模式：集群的默认模式，以本次搭建的集群（nc060，nc078）为例，nc060 和 nc078 拥有相同的元数据，即交换机、队列、绑定等基础结构，但是消息实体只存在于一个节点。
*   镜像模式：将需要消费的队列变为镜像队列，存在于集群的多个节点，这样就可以实现 RabbitMQ 的 HA 高可用性。作用就是消息实体会主动在镜像节点之间实现同步，而不是像普通模式那样，在 consumer 消费数据时临时读取。缺点就是，集群内部的同步通讯会占用网络带宽。

### [](#3-高可用性部署策略 "3. 高可用性部署策略")3. 高可用性部署策略

#### [](#3-1-镜像队列 "3.1 镜像队列")3.1 镜像队列

此部分内容可参考官方文档：[http://www.rabbitmq.com/ha.html](http://www.rabbitmq.com/ha.html)

RabbitMQ 镜像队列的模式如下列表：

| ha-mode | ha-params | Result |
| --- | --- | --- |
| exactly | count | 镜像队列将会在集群上复制 count 份。如果节点数量少于 count，队列会复制到所有节点上。如果节点数量大于 count，有一个镜像节点 crash 后，其余节点也不会作为新的镜像节点。 |
| all | 无 | 镜像队列将会在整个集群节点中复制。当一个新的节点加入集群后，也会在这个节点上复制一份镜像队列。 |
| nodes | node names | 镜像队列会在 node name 中复制。如果这个 node name 不属于集群，不会触发错误。 |

设置镜像队列有两种方式，第一种是在代码里声明队列时设置参数：

```
map.put("x-ha-policy", "all");

channel.queueDeclare(QUEUE_NAME, true, false, false, map);
```

第二种是直接修改系统配置：

```
./rabbitmqctl set_policy ha-all "^" '{"ha-mode":"all"}'
```

#### [](#3-2-RabbitMQ负载均衡部署 "3.2 RabbitMQ负载均衡部署")3.2 RabbitMQ 负载均衡部署

在某台服务器上安装 haproxy

```
yum install haproxy
```

打开 haproxy 的配置文件，/etc/haproxy/haproxy.cfg
加入以下配置：

```
//RabbitMQ链接监听

listen rabbitmq_local_cluster 部署haproxy的机器IP:5670

     mode tcp

     balance roundrobin

     server rabbit_nc078 nc078:5672 check inter 5000 rise 2 fall 3

     server rabbit_nc060 nc060:5672 check inter 5000 rise 2 fall 3

//web管理界面

listen private_monitoring :8100

     mode http

     option httplog

     stats enable

     stats uri       /stats

     stats refresh 10s

     stats auth    user:pwd
```

启动 haproxy：

```
service haproxy start
```

浏览器打开：haproxy 的机器 IP:8100/stats，查看当前的 RabbitMQ 节点的状态：

[![](https://static.zhaoyh.com.cn/haproxy_rabbit.jpg)](https://static.zhaoyh.com.cn/haproxy_rabbit.jpg)

现在已经部署好了负载均衡服务，接下来就可以把你的消息生产者和消费者代码中的配置修改下，之前的 RabbitMQ 链接示例为：

```
nc060:5672 或者 nc078:5672
```

因为在 haproxy 中配置的端口为 5670，现在可以统一修改为：

```
部署haproxy的机器IP:5670
```

至此已经完成了对 RabbitMQ 的集群搭建和高可用模式的初步探索，接下来就请你好好享受消息通信带来的便捷吧！

> 以上内容就是关于 RabbitMQ 集群架构搭建与高可用性实现的全部内容了，谢谢你阅读到了这里！
>
