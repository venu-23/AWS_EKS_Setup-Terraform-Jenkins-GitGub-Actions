# ============================
# EKS CLUSTER (REQUIRED)
# ============================
resource "aws_eks_cluster" "eks" {

  count    = var.is-eks-cluster-enabled == true ? 1 : 0
  name     = var.cluster-name
  role_arn = aws_iam_role.eks-cluster-role[count.index].arn
  version  = var.cluster-version

  vpc_config {
    # REQUIRED: Fargate pods must run in PRIVATE subnets
    subnet_ids = [
      aws_subnet.private-subnet[0].id,
      aws_subnet.private-subnet[1].id,
      aws_subnet.private-subnet[2].id
    ]

    endpoint_private_access = var.endpoint-private-access
    endpoint_public_access  = var.endpoint-public-access

    # REQUIRED: Cluster security group
    security_group_ids = [aws_security_group.eks-cluster-sg.id]
  }

  access_config {
    authentication_mode                         = "CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = {
    Name = var.cluster-name
    Env  = var.env
  }
}

# ============================
# OIDC PROVIDER (REQUIRED)
# ============================
# REQUIRED for:
# - IRSA (IAM Roles for Service Accounts)
# - Most real-world eCommerce workloads
resource "aws_iam_openid_connect_provider" "eks-oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks-certificate.certificates[0].sha1_fingerprint]
  url             = data.tls_certificate.eks-certificate.url
}

# ============================
# EKS ADDONS
# ============================
resource "aws_eks_addon" "eks-addons" {

  # REQUIRED ADDONS FOR FARGATE:
  # - vpc-cni        → REQUIRED (networking)
  # - coredns       → REQUIRED (DNS)
  #
  # NOT REQUIRED FOR FARGATE:
  # - kube-proxy    → OPTIONAL (AWS manages networking internally)

  for_each      = { for idx, addon in var.addons : idx => addon }
  cluster_name  = aws_eks_cluster.eks[0].name
  addon_name    = each.value.name
  addon_version = each.value.version

  depends_on = [
    aws_eks_fargate_profile.fargate
  ]
}

# ============================
# FARGATE PROFILE (REQUIRED)
# ============================
resource "aws_eks_fargate_profile" "fargate" {

  count                = var.is-eks-cluster-enabled ? 1 : 0
  cluster_name         = aws_eks_cluster.eks[0].name
  fargate_profile_name = "${var.cluster-name}-fargate"

  # REQUIRED: IAM role for Fargate pods
  pod_execution_role_arn = aws_iam_role.eks_fargate_pod_execution_role.arn

  # REQUIRED: Must be PRIVATE subnets
  subnet_ids = [
    aws_subnet.private-subnet[0].id,
    aws_subnet.private-subnet[1].id,
    aws_subnet.private-subnet[2].id
  ]

  # REQUIRED: Namespace selector
  selector {
    namespace = "default"
  }

  # REQUIRED: Core system pods run here
  selector {
    namespace = "kube-system"
  }

  depends_on = [aws_eks_cluster.eks]
}

# ============================================================
# NODE GROUPS (NOT NEEDED FOR FARGATE)
# ============================================================
# ❌ DO NOT USE with Fargate-only architecture
# ❌ EC2 nodes are NOT created
# ❌ kubelet runs only on EC2 nodes (not needed)
# ❌ You do NOT manage instance types, scaling, or AMIs
/*
resource "aws_eks_node_group" "ondemand-node" {
  cluster_name    = aws_eks_cluster.eks[0].name
  node_group_name = "${var.cluster-name}-on-demand-nodes"

  node_role_arn = aws_iam_role.eks-nodegroup-role[0].arn

  scaling_config {
    desired_size = var.desired_capacity_on_demand
    min_size     = var.min_capacity_on_demand
    max_size     = var.max_capacity_on_demand
  }

  subnet_ids = [
    aws_subnet.private-subnet[0].id,
    aws_subnet.private-subnet[1].id,
    aws_subnet.private-subnet[2].id
  ]

  instance_types = var.ondemand_instance_types
  capacity_type  = "ON_DEMAND"

  depends_on = [aws_eks_cluster.eks]
}

resource "aws_eks_node_group" "spot-node" {
  cluster_name    = aws_eks_cluster.eks[0].name
  node_group_name = "${var.cluster-name}-spot-nodes"

  node_role_arn = aws_iam_role.eks-nodegroup-role[0].arn

  scaling_config {
    desired_size = var.desired_capacity_spot
    min_size     = var.min_capacity_spot
    max_size     = var.max_capacity_spot
  }

  subnet_ids = [
    aws_subnet.private-subnet[0].id,
    aws_subnet.private-subnet[1].id,
    aws_subnet.private-subnet[2].id
  ]

  instance_types = var.spot_instance_types
  capacity_type  = "SPOT"

  depends_on = [aws_eks_cluster.eks]
}
*/
