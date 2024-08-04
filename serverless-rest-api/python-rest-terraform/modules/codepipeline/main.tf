resource "aws_codepipeline" "terraform_pipeline" {

  name          = "${var.project_name}-pipeline"
  role_arn      = var.codepipeline_role_arn
  pipeline_type = "V2"

  artifact_store {
    location = var.s3_bucket_name
    type     = "S3"
    encryption_key {
      id   = var.kms_key_arn
      type = "KMS"
    }
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      version          = "1"
      provider         = "CodeStarSourceConnection"
      namespace        = "SourceVariables"
      output_artifacts = ["SourceOutput"]
      run_order        = 1

      configuration = {
        ConnectionArn    = var.codestar_connection_arn
        FullRepositoryId = var.source_repo_name
        BranchName       = var.source_repo_branch
      }
    }
  }

  stage {
    name = "Application-Test"

    action {
      name             = "Action-Validate-Application"
      category         = "Test"
      owner            = "AWS"
      version          = "1"
      provider         = "CodeBuild"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["ValidateOutput"]
      run_order        = 2

      configuration = {
        ProjectName = "${var.project_name}-validate"
        EnvironmentVariables : jsonencode([
          {
            "name" : "TF_VAR_tf_state_bucket",
            "value" : "${var.s3_bucket_name}"
          },
          {
            "name" : "TF_VAR_tf_state_table",
            "value" : "${var.dynamodb_table_name}"
          },
          {
            "name" : "TF_VAR_serverless_application_name",
            "value" : "my-app"
          },
          {
            "name" : "TF_VAR_cognito_stack_name",
            "value" : "${var.project_name}-Cognito-Testing"
          },
          {
            "name" : "TF_VAR_region",
            "value" : "${var.region}"
          },
          {
            "name" : "TF_VAR_environment",
            "value" : "test"
          }
        ])
      }
    }
    action {
      name             = "Action-Plan-Application"
      category         = "Test"
      owner            = "AWS"
      version          = "1"
      provider         = "CodeBuild"
      input_artifacts  = ["ValidateOutput"]
      output_artifacts = ["PlanOutput"]
      run_order        = 3

      configuration = {
        ProjectName = "${var.project_name}-plan"
        EnvironmentVariables : jsonencode([
          {
            "name" : "TF_VAR_tf_state_bucket",
            "value" : "${var.s3_bucket_name}"
          },
          {
            "name" : "TF_VAR_tf_state_table",
            "value" : "${var.dynamodb_table_name}"
          },
          {
            "name" : "TF_VAR_serverless_application_name",
            "value" : "my-app"
          },
          {
            "name" : "TF_VAR_cognito_stack_name",
            "value" : "${var.project_name}-Cognito-Testing"
          },
          {
            "name" : "TF_VAR_region",
            "value" : "${var.region}"
          },
          {
            "name" : "TF_VAR_environment",
            "value" : "test"
          }
        ])
      }
    }
  }

  stage {
    name = "Cognito-Setup"

    action {
      name            = "Action-Create-Cognito-ChangeSet"
      category        = "Deploy"
      owner           = "AWS"
      version         = "1"
      provider        = "CloudFormation"
      input_artifacts = ["PlanOutput"]
      run_order       = 4

      configuration = {
        ActionMode    = "CHANGE_SET_REPLACE",
        RoleArn       = var.cloudformation_role_arn,
        StackName     = "${var.project_name}-Cognito-Testing",
        ChangeSetName = "${var.project_name}-ChangeSet-Cognito-Testing",
        TemplatePath  = "PlanOutput::shared/cognito.yaml",
        Capabilities  = "CAPABILITY_IAM"
      }
    }
    action {
      name             = "Action-Execute-Cognito-ChangeSet"
      category         = "Deploy"
      owner            = "AWS"
      version          = "1"
      provider         = "CloudFormation"
      input_artifacts  = ["PlanOutput"]
      output_artifacts = ["${var.project_name}CognitoTestingChangeSet"]
      run_order        = 5

      configuration = {
        ActionMode    = "CHANGE_SET_EXECUTE",
        RoleArn       = var.cloudformation_role_arn,
        StackName     = "${var.project_name}-Cognito-Testing",
        ChangeSetName = "${var.project_name}-ChangeSet-Cognito-Testing",
        TemplatePath  = "PlanOutput::cognito.yaml",
        Capabilities  = "CAPABILITY_IAM"
      }
    }
  }

  stage {
    name = "Application-Deploy"

    action {
      name             = "Action-Apply-Application"
      category         = "Build"
      owner            = "AWS"
      version          = "1"
      provider         = "CodeBuild"
      input_artifacts  = ["PlanOutput"]
      output_artifacts = ["ApplyOutput"]
      run_order        = 6

      configuration = {
        ProjectName = "${var.project_name}-apply"
      }
    }
  }

  stage {
    name = "Destroy"

    action {
      name      = "Action-Destroy-Approval"
      category  = "Approval"
      owner     = "AWS"
      version   = "1"
      provider  = "Manual"
      run_order = 7
    }
    action {
      name             = "Action-Destroy-Application"
      category         = "Build"
      owner            = "AWS"
      version          = "1"
      provider         = "CodeBuild"
      input_artifacts  = ["ApplyOutput"]
      output_artifacts = ["DestroyOutput"]
      run_order        = 8

      configuration = {
        ProjectName = "${var.project_name}-destroy"
      }
    }
    action {
      name            = "Action-Destroy-Cognito-ChangeSet"
      category        = "Deploy"
      owner           = "AWS"
      version         = "1"
      provider        = "CloudFormation"
      input_artifacts = ["DestroyOutput"]
      run_order       = 9

      configuration = {
        ActionMode = "DELETE_ONLY",
        RoleArn    = var.cloudformation_role_arn,
        StackName  = "${var.project_name}-Cognito-Testing",
      }
    }
  }

}