#!/bin/bash
#yum update -y
#######################################################################################################################################################
### This bootstrap script runs on glusterFS server and configures the following
### 1- install gluster packages
### 2- formats the NVME disks (HighIO1.36 shape), creates a LVM LV called "brick" (XFS)
### 3- fixes the resolve.conf file. GlusterFS needs DNS to work properly so make sure you update the below domains to match your environment
### 4- disable local firewall. Feel free to update this script to open only the required ports.
### 5- install and configure a gluster volume called glustervol using server1-mybrick, server2-mybrick and server3-mybrick LVs (replicas)
###
######################################################################################################################################################
exec 2>/dev/null

node1=$1
node2=$2


create_pvolume()
{
    if [ `lsblk -d --noheadings | awk '{print $1}' | grep nvme0n1` = "nvme0n1" ]; then NVME=true; else NVME=false; fi
    for i in `lsblk -d --noheadings | awk '{print $1}'`
    do
        if [ $i = "sda" ]; then next
        else
            pvcreate --dataalignment 256K /dev/$i
            vgcreate vg_gluster /dev/$i
            vgextend vg_gluster /dev/$i
        fi
    done

    vgdisplay
    config_gluster
}

config_gluster()
{
    echo CONFIG GLUSTER
    lvcreate -y -l 100%VG --stripes 8 -n brick1 vg_gluster
    lvdisplay
    mkfs.xfs -f -i size=512 /dev/vg_gluster/brick1
    mkdir -p /bricks/brick1
    mount -o noatime,inode64 /dev/vg_gluster/brick1 /bricks/brick1
    echo "/dev/vg_gluster/brick1  /bricks/brick1    xfs     noatime,inode64  1 2" >> /etc/fstab
    df -h
    sed -i '/search/d' /etc/resolv.conf
    echo "search baremetal.oraclevcn.com gluster_subnet-d6700.baremetal.oraclevcn.com publicsubnetad1.baremetal.oraclevcn.com publicsubnetad3.baremetal.oraclevcn.com localdomain" >> /etc/resolv.conf
    chattr -R +i /etc/resolv.conf
    #firewall-cmd --zone=public --add-port=24007-24020/tcp --permanent
    #firewall-cmd --reload
    systemctl disable firewalld
    systemctl stop firewalld
    systemctl enable glusterd.service
    systemctl start glusterd.service
    mkdir /bricks/brick1/brick

    if [ "$(hostname -s | tail -c 3)" = "-1" ]; then
        echo CONFIGURING GLUSTER SERVER
        sleep 60
        host=`hostname -i`
        for i in `seq 2 $server_nodes`;
        do
            gluster peer probe $subnet.1$i
        done
        sleep 20
        gluster volume create glustervol transport tcp ${node1}:/bricks/brick1/brick force
        sleep 10
        for i in `seq 2 $server_nodes`;
        do
            gluster volume add-brick glustervol ${node2}:/bricks/brick1/brick force
            sleep 10
        done
        gluster volume start glustervol force
        sleep 20
        gluster volume start glustervol force
        gluster volume status
        gluster volume info
    fi
}

create_pvolume