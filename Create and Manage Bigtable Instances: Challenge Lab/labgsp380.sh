#!/bin/bash

# Show current authentication
echo "Current gcloud authentication:"
gcloud auth list
echo

# Set environment variables
echo "Setting up environment variables..."
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)

# Configure Dataflow service
echo "Configuring Dataflow service..."
gcloud services disable dataflow.googleapis.com --project $DEVSHELL_PROJECT_ID
gcloud config set compute/zone "$ZONE"
gcloud config set compute/region "$REGION"
gcloud services enable dataflow.googleapis.com --project $DEVSHELL_PROJECT_ID

# Bigtable instance creation prompt
echo
echo "Create Bigtable instance https://console.cloud.google.com/bigtable/create-instance?project=$DEVSHELL_PROJECT_ID"
echo

while true; do
    echo -ne "Do you want to proceed? (Y/n): "
    read confirm
    case "$confirm" in
        [Yy]) 
            echo "Running the command..."
            break
            ;;
        [Nn]|"") 
            echo "Operation canceled."
            exit 0
            ;;
        *) 
            echo "Invalid input. Please enter Y or N." 
            ;;
    esac
done

# Create storage bucket
echo "Creating storage bucket..."
gsutil mb gs://$PROJECT_ID

# Create Bigtable tables
echo "Creating Bigtable tables..."
gcloud bigtable instances tables create SessionHistory --instance=ecommerce-recommendations --project=$PROJECT_ID --column-families=Engagements,Sales
sleep 20

# Import sessions data
echo "Importing sessions data..."
while true; do
    gcloud dataflow jobs run import-sessions --region=$REGION --project=$PROJECT_ID \
        --gcs-location gs://dataflow-templates-$REGION/latest/GCS_SequenceFile_to_Cloud_Bigtable \
        --staging-location gs://$PROJECT_ID/temp \
        --parameters bigtableProject=$PROJECT_ID,bigtableInstanceId=ecommerce-recommendations,bigtableTableId=SessionHistory,sourcePattern=gs://cloud-training/OCBL377/retail-engagements-sales-00000-of-00001,mutationThrottleLatencyMs=0

    if [ $? -eq 0 ]; then
        echo "Job has completed successfully. Now just wait for succeeded https://www.youtube.com/@drabhishek.5460"
        break
    else
        echo "Job retrying. Please like, share and subscribe to Dr. Abhishek Cloud Tutorials https://www.youtube.com/@drabhishek.5460"
        sleep 10
    fi
done

# Create recommendations table
echo "Creating recommendations table..."
gcloud bigtable instances tables create PersonalizedProducts --project=$PROJECT_ID --instance=ecommerce-recommendations --column-families=Recommendations
sleep 20

# Import recommendations data
echo "Importing recommendations data..."
while true; do
    gcloud dataflow jobs run import-recommendations --region=$REGION --project=$PROJECT_ID \
        --gcs-location gs://dataflow-templates-$REGION/latest/GCS_SequenceFile_to_Cloud_Bigtable \
        --staging-location gs://$PROJECT_ID/temp \
        --parameters bigtableProject=$PROJECT_ID,bigtableInstanceId=ecommerce-recommendations,bigtableTableId=PersonalizedProducts,sourcePattern=gs://cloud-training/OCBL377/retail-recommendations-00000-of-00001,mutationThrottleLatencyMs=0

    if [ $? -eq 0 ]; then
        echo "Job has completed successfully. Now just wait for succeeded https://www.youtube.com/@drabhishek.5460"
        break
    else
        echo "Job retrying. Please like, share and subscribe to Dr. Abhishek Cloud Tutorials https://www.youtube.com/@drabhishek.5460"
        sleep 10
    fi
done

# Create backup
echo "Creating backup..."
gcloud beta bigtable backups create PersonalizedProducts_7 --instance=ecommerce-recommendations --cluster=ecommerce-recommendations-c1 --table=PersonalizedProducts --retention-period=7d 

# Restore backup
echo "Restoring backup..."
gcloud beta bigtable instances tables restore --source=projects/$PROJECT_ID/instances/ecommerce-recommendations/clusters/ecommerce-recommendations-c1/backups/PersonalizedProducts_7 --async --destination=PersonalizedProducts_7_restored --destination-instance=ecommerce-recommendations --project=$PROJECT_ID

# Check job status prompt
echo
echo "Check job status https://console.cloud.google.com/dataflow/jobs?project=$DEVSHELL_PROJECT_ID"
echo

echo "Be careful here! Proceed only after all the 4 steps are completed!!"

while true; do
    echo -ne "Do you want to proceed with cleanup? (Y/n): "
    read confirm
    case "$confirm" in
        [Yy]) 
            echo "Running cleanup commands..."
            break
            ;;
        [Nn]|"") 
            echo "Cleanup canceled."
            exit 0
            ;;
        *) 
            echo "Invalid input. Please enter Y or N." 
            ;;
    esac
done

# Cleanup resources
echo "Cleaning up resources..."
gcloud bigtable instances tables delete PersonalizedProducts --instance=ecommerce-recommendations --quiet
gcloud bigtable instances tables delete PersonalizedProducts_7_restored --instance=ecommerce-recommendations --quiet
gcloud bigtable instances tables delete SessionHistory --instance=ecommerce-recommendations --quiet
gcloud bigtable backups delete PersonalizedProducts_7 \
  --instance=ecommerce-recommendations \
  --cluster=ecommerce-recommendations-c1 --quiet

echo
