provider "aws" {
  region = "us-east-1"
}

resource "null_resource" "build-layer" {
  provisioner "local-exec" {
    command = <<EOT
      echo "Starting layer creation..."
      if [ ! -f layer/python ]; then
        mkdir -p layer/python
        echo "Installing packages..."
        pip3 install --platform manylinux2014_x86_64 \
           --target=layer/python \
           --implementation cp \
           --python-version 3.12 \
           --only-binary=:all: \
           --upgrade \
           openai pinecone
        echo "Packages installed."
      else
        echo "Layer already exists."
      fi
      echo "Layer creation complete."
    EOT
  }
}

data "archive_file" "zip-layer" {
  type        = "zip"
  source_dir  = "${path.module}/layer"
  output_path = "${path.module}/library.zip"
  depends_on  = [null_resource.build-layer]
}

resource "aws_lambda_layer_version" "layer" {
  filename                  = data.archive_file.zip-layer.output_path
  layer_name                = "openai-pinecone"
  compatible_runtimes       = ["python3.12"]
  compatible_architectures  = ["x86_64"]
  source_code_hash          = data.archive_file.zip-layer.output_base64sha256
}

output "layer" {
 value = aws_lambda_layer_version.layer.arn
}
