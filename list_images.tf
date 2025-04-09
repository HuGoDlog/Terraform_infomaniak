data "openstack_images_image_ids_v2" "images" {
  name_regex = ".*"
  sort       = "name"
}

output "available_images" {
  value = data.openstack_images_image_ids_v2.images.ids
}
