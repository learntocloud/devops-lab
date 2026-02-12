terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "random_id" "deployment" {
  byte_length = 4
}

resource "aws_vcp" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "vpc-devopslab-${random_id.deployment.hex}"
  }
}

resource "aws_subnet" "eks_a" {
  vpc_id                  = aws_vcp.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  tags = {
    Name = "snet-eks-a"
  }
}

resource "aws_subnet" "eks_b" {
  vpc_id                  = aws_vcp.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.region}b"
  tags = {
    Name = "snet-eks-b"
  }
}

resource "aws_ecr_repository" "main" {
  name = "devopslab-${random_id.deployment.hex}"
}

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/devopslab-${random_id.deployment.hex}"
  retention_in_days = 30
}

resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster-role-${random_id.deployment.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSCluserPolicy"
}

resource "aws_iam_role" "eks_node" {
  name = "eks-node-role-${random_id.deployment.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_cluster" "main" {
  name     = "eks-devopslab-${random_id.deployment.hex}"
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = [aws_subnet.eks_a.id, aws_subnet.eks_b.id]
  }

  kubernetes_network_config {
    service_ipv4_cidr = "10.0.0.0/16"
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "ng-devopslab-${random_id.deployment.hex}"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = [aws_subnet.eks_a.id, aws_subnet.eks_b.id]

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  instance_types = ["t3.medium"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_policy
  ]
}
