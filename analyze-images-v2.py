import os
import sys

# Import Google Cloud Library modules
from google.cloud import storage, bigquery, language, vision, translate_v2

if ('GOOGLE_APPLICATION_CREDENTIALS' in os.environ):
    if (not os.path.exists(os.environ['GOOGLE_APPLICATION_CREDENTIALS'])):
        print("The GOOGLE_APPLICATION_CREDENTIALS file does not exist.\n")
        exit()
else:
    print("The GOOGLE_APPLICATION_CREDENTIALS environment variable is not defined.\n")
    exit()

if len(sys.argv) < 3:
    print('You must provide parameters for the Google Cloud project ID and Storage bucket')
    print('python3 ' + sys.argv[0] + ' [PROJECT_NAME] [BUCKET_NAME]')
    exit()

project_name = sys.argv[1]
bucket_name = sys.argv[2]

# Set up clients
storage_client = storage.Client()
bq_client = bigquery.Client(project=project_name)
vision_client = vision.ImageAnnotatorClient()
translate_client = translate_v2.Client()

# BigQuery dataset and table
dataset_ref = bq_client.dataset('image_classification_dataset')
table_ref = dataset_ref.table('image_text_detail')
table = bq_client.get_table(table_ref)

rows_for_bq = []

# Get list of files in bucket
bucket = storage_client.bucket(bucket_name)
files = bucket.list_blobs()

print('Processing image files from GCS. This will take a few minutes...')

for file in files:
    if file.name.endswith(('jpg', 'png')):
        file_content = file.download_as_string()

        # Vision API detect text
        image = vision.Image(content=file_content)
        response = vision_client.text_detection(image=image)

        if not response.text_annotations:
            continue

        desc = response.text_annotations[0].description
        locale = response.text_annotations[0].locale

        # Translate only if not French
        if locale != 'fr':
            translation = translate_client.translate(desc, target_language="fr")
            translated_text = translation['translatedText']
        else:
            translated_text = desc

        print(f"File: {file.name}, Locale: {locale}, Translated: {translated_text}")

        # Save results for BigQuery
        rows_for_bq.append({
            "original_text": desc,
            "locale": locale,
            "translated_text": translated_text,
            "filename": file.name
        })

print('Writing Vision API + Translation results to BigQuery...')

# Insert into BigQuery
errors = bq_client.insert_rows_json(table, rows_for_bq)

if errors == []:
    print("✅ Data successfully inserted into BigQuery")
else:
    print("❌ Errors occurred:", errors)
