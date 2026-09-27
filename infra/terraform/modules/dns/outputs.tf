output "active_target" {
  description = "Side that receives traffic with the current weights: onprem or aws."
  value       = var.traffic_weights.aws == 100 ? "aws" : "onprem"
}

output "record_names" {
  description = "Names managed as weighted pairs."
  value       = sort(keys(var.records))
}
