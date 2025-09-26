output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public-subnet[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private-subnet[*].id
}

output "private-rt_id" {
  value = aws_route_table.private-rt.id
}

output "public-rt_id" {
  value = aws_route_table.public-rt.id
}

# output for eks
output "eks_cluster_name" {
  value = aws_eks_cluster.eks_cluster.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.eks_cluster.endpoint
}

output "eks_cluster_ca" {
  value = aws_eks_cluster.eks_cluster.certificate_authority[0].data
}
