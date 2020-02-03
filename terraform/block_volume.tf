
/*
Copyright © 2018, Oracle and/or its affiliates. All rights reserved.
The Universal Permissive License (UPL), Version 1.0
*/

resource "oci_core_volume" "gluster_blockvolume" {
  count = var.gluster_server["node_count"] * var.gluster_server["brick_count"]

availability_domain = data.oci_identity_availability_domains.ADs.availability_domains[((count.index % var.gluster_server["node_count"])%3)]["name"]
#availability_domain = data.oci_identity_availability_domains.ADs.availability_domains[var.AD - 1]["name"]

  compartment_id      = var.compartment_ocid
  display_name        = "server${count.index % var.gluster_server["node_count"] + 1}-brick${count.index % var.gluster_server["brick_count"] + 1}"
  size_in_gbs         = "${var.gluster_server["brick_size"]}"
  vpus_per_gb         = var.gluster_server["vpus_per_gb"]
}

resource "oci_core_volume_attachment" "blockvolume_attach" {
  attachment_type = "iscsi"
  count = var.gluster_server["node_count"] * var.gluster_server["brick_count"]
  instance_id = element(
    oci_core_instance.gluster_server.*.id,
    count.index % var.gluster_server["node_count"],
  )
  volume_id = element(oci_core_volume.gluster_blockvolume.*.id, count.index)

  provisioner "remote-exec" {
    connection {
      agent   = false
      timeout = "30m"
      host = element(
        oci_core_instance.gluster_server.*.private_ip,
        count.index % var.gluster_server["node_count"],
      )
      user                = var.ssh_user
      private_key         = var.ssh_private_key
      bastion_host        = oci_core_instance.bastion[0].public_ip
      bastion_port        = "22"
      bastion_user        = var.ssh_user
      bastion_private_key = var.ssh_private_key
    }

    inline = [
      "sudo -s bash -c 'set -x && iscsiadm -m node -o new -T ${self.iqn} -p ${self.ipv4}:${self.port}'",
      "sudo -s bash -c 'set -x && iscsiadm -m node -o update -T ${self.iqn} -n node.startup -v automatic '",
      "sudo -s bash -c 'set -x && iscsiadm -m node -T ${self.iqn} -p ${self.ipv4}:${self.port} -l '",
    ]
  }
}


/*
  Notify server nodes that all block-attach is complete, so  server nodes can continue with their rest of the instance setup logic in cloud-init.
*/
resource "null_resource" "notify_server_nodes_block_attach_complete" {
  depends_on = [ oci_core_volume_attachment.blockvolume_attach ]
  count = var.gluster_server["node_count"]
  provisioner "remote-exec" {
    connection {
        agent               = false
        timeout             = "30m"
        host                = "${element(oci_core_instance.gluster_server.*.private_ip, count.index)}"
        user                = "${var.ssh_user}"
        private_key         = "${var.ssh_private_key}"
        bastion_host        = "${oci_core_instance.bastion.*.public_ip[0]}"
        bastion_port        = "22"
        bastion_user        = "${var.ssh_user}"
        bastion_private_key = "${var.ssh_private_key}"
    }
    inline = [
      "set -x",
      "sudo touch /tmp/block-attach.complete",
    ]
  }
}