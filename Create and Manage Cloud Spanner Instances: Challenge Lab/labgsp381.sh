#!/bin/bash

# Create Spanner instance
echo "Creating Spanner instance: banking-ops-instance"
gcloud spanner instances create banking-ops-instance \
  --config=regional-$REGION \
  --description="DP" \
  --nodes=1

# Create database
echo "Creating database: banking-ops-db"
gcloud spanner databases create banking-ops-db --instance=banking-ops-instance

# Create tables
echo "Creating database tables"
gcloud spanner databases ddl update banking-ops-db --instance=banking-ops-instance \
  --ddl="CREATE TABLE Portfolio (
    PortfolioId INT64 NOT NULL,
    Name STRING(MAX),
    ShortName STRING(MAX),
    PortfolioInfo STRING(MAX))
    PRIMARY KEY (PortfolioId)"

gcloud spanner databases ddl update banking-ops-db --instance=banking-ops-instance \
  --ddl="CREATE TABLE Category (
    CategoryId INT64 NOT NULL,
    PortfolioId INT64 NOT NULL,
    CategoryName STRING(MAX),
    PortfolioInfo STRING(MAX))
    PRIMARY KEY (CategoryId)"

gcloud spanner databases ddl update banking-ops-db --instance=banking-ops-instance \
  --ddl="CREATE TABLE Product (
    ProductId INT64 NOT NULL,
    CategoryId INT64 NOT NULL,
    PortfolioId INT64 NOT NULL,
    ProductName STRING(MAX),
    ProductAssetCode STRING(25),
    ProductClass STRING(25))
    PRIMARY KEY (ProductId)"

gcloud spanner databases ddl update banking-ops-db --instance=banking-ops-instance \
  --ddl="CREATE TABLE Customer (
    CustomerId STRING(36) NOT NULL,
    Name STRING(MAX) NOT NULL,
    Location STRING(MAX) NOT NULL)
    PRIMARY KEY (CustomerId)"

# Insert sample data
echo "Inserting sample data"
gcloud spanner databases execute-sql banking-ops-db --instance=banking-ops-instance \
  --sql='INSERT INTO Portfolio (PortfolioId, Name, ShortName, PortfolioInfo)
  VALUES 
    (1, "Banking", "Bnkg", "All Banking Business"),
    (2, "Asset Growth", "AsstGrwth", "All Asset Focused Products"),
    (3, "Insurance", "Insurance", "All Insurance Focused Products")'

gcloud spanner databases execute-sql banking-ops-db --instance=banking-ops-instance \
  --sql='INSERT INTO Category (CategoryId, PortfolioId, CategoryName)
  VALUES 
    (1, 1, "Cash"),
    (2, 2, "Investments - Short Return"),
    (3, 2, "Annuities"),
    (4, 3, "Life Insurance")'

gcloud spanner databases execute-sql banking-ops-db --instance=banking-ops-instance \
  --sql='INSERT INTO Product (ProductId, CategoryId, PortfolioId, ProductName, ProductAssetCode, ProductClass)
  VALUES 
    (1, 1, 1, "Checking Account", "ChkAcct", "Banking LOB"),
    (2, 2, 2, "Mutual Fund Consumer Goods", "MFundCG", "Investment LOB"),
    (3, 3, 2, "Annuity Early Retirement", "AnnuFixed", "Investment LOB"),
    (4, 4, 3, "Term Life Insurance", "TermLife", "Insurance LOB"),
    (5, 1, 1, "Savings Account", "SavAcct", "Banking LOB"),
    (6, 1, 1, "Personal Loan", "PersLn", "Banking LOB"),
    (7, 1, 1, "Auto Loan", "AutLn", "Banking LOB"),
    (8, 4, 3, "Permanent Life Insurance", "PermLife", "Insurance LOB"),
    (9, 2, 2, "US Savings Bonds", "USSavBond", "Investment LOB")'

# Download customer data
echo "Downloading customer data"
curl -LO https://raw.githubusercontent.com/dikshapc/Google-Cloud-Skill-Badge-Solutions/main/Create%20and%20Manage%20Cloud%20Spanner%20Instances%3A%20Challenge%20Lab/Customer_List_500.csv

# Prepare Dataflow
echo "Preparing Dataflow service"
gcloud services disable dataflow.googleapis.com --force
gcloud services enable dataflow.googleapis.com

# Create manifest file
echo "Creating import manifest"
cat > manifest.json << EOF_CP
{
  "tables": [
    {
      "table_name": "Customer",
      "file_patterns": [
        "gs://$DEVSHELL_PROJECT_ID/Customer_List_500.csv"
      ],
      "columns": [
        {"column_name" : "CustomerId", "type_name" : "STRING" },
        {"column_name" : "Name", "type_name" : "STRING" },
        {"column_name" : "Location", "type_name" : "STRING" }
      ]
    }
  ]
}
EOF_CP

# Prepare GCS bucket
echo "Preparing Cloud Storage bucket"
gsutil mb gs://$DEVSHELL_PROJECT_ID

# Create placeholder file
echo "Creating placeholder files"
touch dptest
gsutil cp dptest gs://$DEVSHELL_PROJECT_ID/tmp/dptest

# Upload files to GCS
echo "Uploading files to Cloud Storage"
gsutil cp Customer_List_500.csv gs://$DEVSHELL_PROJECT_ID
gsutil cp manifest.json gs://$DEVSHELL_PROJECT_ID

# Wait for operations to complete
echo "Waiting for setup to complete..."
sleep 100

# Run Dataflow job
echo "Running Dataflow import job"
gcloud dataflow jobs run dptest \
  --gcs-location gs://dataflow-templates-"$REGION"/latest/GCS_Text_to_Cloud_Spanner \
  --region="$REGION" \
  --staging-location gs://$DEVSHELL_PROJECT_ID/tmp/ \
  --parameters instanceId=banking-ops-instance,databaseId=banking-ops-db,importManifest=gs://$DEVSHELL_PROJECT_ID/manifest.json

# Update schema
echo "Updating database schema"
gcloud spanner databases ddl update banking-ops-db --instance=banking-ops-instance \
  --ddl='ALTER TABLE Category ADD COLUMN MarketingBudget INT64;'

# Completion message
echo "Lab Completed Successfully"
