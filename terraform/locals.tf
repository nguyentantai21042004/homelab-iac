# Các giá trị cố định, biết trước
locals {
  port_groups = {
    vm_network         = "VM Network"
    management_network = "Management Network"
    db_network         = "DB-Network"
    prod_network       = "Prod-Network"
  }
}
