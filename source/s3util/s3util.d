module s3util;

import std.container;
import std.conv;
import std.string;
import std.process;
import std.algorithm;
import std.typecons;

import s3;

unittest { import std.stdio; writeln(__MODULE__, " : test start"); }

T ifNullOr(T, U)(U u, T t, T e)
{
	return u == null ? t : e;
}

shared string DefaultAccessKeyIdG;
shared string DefaultSecretAccessKeyIdG;

struct PutCallbackData
{
	const char[] buffer;
	size_t read;
}

struct ListServiceCallbackData
{
	DList!(S3.Bucket) buckets;
	S3 s3;
}

shared static this()
{
	string userAgentInfo = "s3";

	string defaultS3Hostname = environment.get("S3_HOSTNAME", null);

	S3_initialize(
		toStringz(userAgentInfo),
		S3_INIT_ALL,
		ifNullOr(defaultS3Hostname, null, toStringz(defaultS3Hostname))
		);

	DefaultAccessKeyIdG = environment.get("S3_ACCESS_KEY_ID");
	DefaultSecretAccessKeyIdG = environment.get("S3_SECRET_ACCESS_KEY");
}

extern(C)
{
	// call backs
	S3Status responsePropertiesCallback(
		const S3ResponseProperties* properties, void* data)
	{
		return S3Status.S3StatusOK;
	}

	void responseCompleteCallback(
		S3Status status, const S3ErrorDetails* error, void* data)
	{
	}

	S3Status listServiceCallback(
		const(char*) ownerId, const(char*) ownerDisplayName,
		const(char*) bucketName, long creationDate, void* data)
	{
		ListServiceCallbackData* callbackData = cast(ListServiceCallbackData*)data;

		S3.Bucket.Info info = {
			to!string(ownerId),
			to!string(ownerDisplayName),
			creationDate
			};

		callbackData.buckets.insert(
			callbackData.s3.new Bucket(to!string(bucketName), info) );

		return S3Status.S3StatusOK;
	}

	int putObjectDataCallback(
		int bufferSize, char* buffer, void* data)
	{
		PutCallbackData* callbackData = cast(PutCallbackData*)data;

		int toRead = min(bufferSize, callbackData.buffer.sizeof - callbackData.read);

		if(toRead)
		{
			for(int i = 0; i < toRead; ++i)
			{
				buffer[i] = callbackData.buffer[callbackData.read + i];
			}

			callbackData.read += toRead;
		}

		import std.stdio;
		writeln("put callback ", toRead, "bytes");

		return toRead;
	}

	S3Status listBucketCallback(
		int isTruncated, const char *nextMarker, int contentsCount, 
		const S3ListBucketContent *contents, int commonPrefixesCount,
		const char **commonPrefixes, void *callbackData)
	{
		pragma(msg, "todo: implement isTruncated, nextMarker, commonPrefixes");

		DList!(S3.ObjectInfo)* infos = cast(DList!(S3.ObjectInfo)*)callbackData;

		for(int i = 0; i < contentsCount; ++i)
		{
			S3.ObjectInfo info =
			{
				to!string(contents[i].key),
				contents[i].lastModified,
				to!string(contents[i].eTag),
				contents[i].size,
				to!string(contents[i].ownerId),
				to!string(contents[i].ownerDisplayName)
			};

			infos.insert(info);
		}

		return S3Status.S3StatusOK;
	}
}

class S3
{
	static shared immutable(string) usEast1 = "us-east-1";
	static shared immutable(string) usWest1 = "us-west-1";
	static shared immutable(string) euWest1 = "eu-west-1";
	static shared immutable(string) euCentral1 = "eu-central-1";
	static shared immutable(string) apSoutheast1 = "ap-southeast-1";
	static shared immutable(string) apSoutheast2 = "ap-southeast-2";
	static shared immutable(string) apNortheast1 = "ap-northeast-1";
	static shared immutable(string) saWest1 = "sa-west-1";

	this()
	{
		accessKeyId = DefaultAccessKeyIdG;
		secretAccessKey = DefaultSecretAccessKeyIdG;
	}

	this(string accessKeyId, string secretAccessKey)
	{
		this.accessKeyId = accessKeyId;
		this.secretAccessKey = secretAccessKey;
	}

	DList!Bucket list()
	{
		DList!Bucket services;

		S3ListServiceHandler listServiceHandler =
		{
			{
				&responsePropertiesCallback,
				&responseCompleteCallback
			},
			&listServiceCallback
		};

		S3_list_service(
			protocol, toStringz(accessKeyId), toStringz(secretAccessKey),
			null, null, &listServiceHandler, &services);

		return services;
	}

	Bucket bucket(string bucketName)
	{
		return new Bucket(bucketName);
	}

	class Bucket
	{
		this(string bucketName)
		{
			this.name = bucketName;
		}

		this(string bucketName, Info info)
		{
			this.name = bucketName;
			this.info = info;
		}

		void put(string key, const char[] data)
		{
			S3PutObjectHandler putObjectHandler =
			{
				{
					&responsePropertiesCallback,
					&responseCompleteCallback
				},
				&putObjectDataCallback
			};

			auto bucketContext = makeBucketContext(name);

			S3PutProperties putProperties =
			{
				null, null, null, null, null, -1,
				S3CannedAcl.S3CannedAclPrivate,
				0, null, 0
			};

			PutCallbackData callbackData = {data, 0};

			S3_put_object(&bucketContext, toStringz(key), data.length,
				&putProperties, null, &putObjectHandler, cast(void*)&callbackData);
		}

		DList!ObjectInfo list()
		{
			S3ListBucketHandler listBucketHandler =
			{
				{
					&responsePropertiesCallback,
					&responseCompleteCallback
				},
				&listBucketCallback
			};

			auto bucketContext = makeBucketContext(name);

			DList!ObjectInfo l;

			S3_list_bucket(
				&bucketContext, null, null, null, 500,
				null, &listBucketHandler, cast(void*)&l);

			return l;
		}

		Bucket create()
		{
			S3ResponseHandler handler =
			{
				&responsePropertiesCallback,
				&responseCompleteCallback
			};
			S3_create_bucket(protocol,
				toStringz(accessKeyId), toStringz(secretAccessKey),
				null, toStringz(name), S3CannedAcl.S3CannedAclPrivate, 
				null, null, &handler, null);

			return this;
		}

		string name;

		Nullable!Info info;

		struct Info
		{
			string ownerId;
			string ownerDisplayName;
			ulong creationDate;
		}
	}

	class ObjectUnit
	{
		ObjectUnit updateInfo()
		{
			pragma(msg, "to be implemented");
			return this;
		}

		char[] get()
		{
			pragma(msg, "to be implemented");
			char[] arr = [1];
			return arr;
		}

		string key;
		Nullable!Info info;

		struct Info
		{
			long lastModified;
			string eTag;
			ulong size;
			string ownerId;
			string ownerDisplayName;
		}
	}

	struct ObjectInfo
	{
		string key;
		long lastModified;
		string eTag;
		ulong size;
		string ownerId;
		string ownerDisplayName;
	}

private:
	string accessKeyId;
	string secretAccessKey;
	S3Protocol protocol = S3Protocol.S3ProtocolHTTPS;
	S3UriStyle uriStyle = S3UriStyle.S3UriStyleVirtualHost;

	S3BucketContext makeBucketContext(string bucketName)
	{
		S3BucketContext result = {
			null,
			toStringz(bucketName),
			protocol,
			uriStyle,
			toStringz(accessKeyId),
			toStringz(secretAccessKey)
		};
		return result;
	}
}

unittest { import std.stdio; writeln(__MODULE__, " : test clear"); }

