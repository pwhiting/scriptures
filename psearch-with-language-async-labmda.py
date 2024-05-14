import json
import numpy as np
import boto3
import asyncio
from openai import OpenAI
from pinecone import Pinecone
from concurrent.futures import ThreadPoolExecutor

def get_secret(secret_name):
    client = boto3.client('secretsmanager')
    try:
        get_secret_value_response = client.get_secret_value(SecretId=secret_name)
    except Exception as e:
        print(f"An error occurred while fetching secret: {e}")
        return None
    secret = get_secret_value_response['SecretString']
    return json.loads(secret)

secrets = get_secret("my_secrets")
if secrets:
    api_key = secrets.get('PINECONE_API_KEY')
    openai_api_key = secrets.get('OPENAI_API_KEY')

client = OpenAI()
pc = Pinecone(api_key=api_key)
index = pc.Index("scriptures")

def translate_sync(text, lang):
    try:
        answer = client.chat.completions.create(
            messages=[{
                "role": "user",
                "content": f"Translate the following English text to {lang}: {text}",
            }],
            model="gpt-4o-turbo",
        )
        return answer.choices[0].message.content
    except Exception as e:
        print(f"An error occurred: {e}")
        return None

async def translate(text, lang):
    loop = asyncio.get_event_loop()
    with ThreadPoolExecutor() as pool:
        result = await loop.run_in_executor(pool, translate_sync, text, lang)
        return result

def embed(text):
    response = client.embeddings.create(
        input=text,
        model="text-embedding-ada-002"
    )
    return response.data[0].embedding

async def lang_vec(q):
    translations = [q] + list(await asyncio.gather(
        translate(q, "spanish"),
        translate(q, "mandarin"),
        translate(q, "korean"),
        translate(q, "hebrew")
    ))
    embeds = [embed(text) for text in translations]
    return np.mean(embeds, axis=0).tolist()

async def handler(event, context):
    query = event.get("query", "")
    docs = index.query(vector=await lang_vec(query), top_k=10, include_metadata=True)
    results = []
    for doc in docs['matches']:
        results.append({
            "reference": doc['metadata']['reference'],
            "text": doc['metadata']['text']
        })
    return {
        "statusCode": 200,
        "body": json.dumps(results)
    }

