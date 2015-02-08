import std.stdio;
import s3util;


void testPhase1()
{
	auto s3 = new S3;

	{
		writeln("list service test");
		auto buckets = s3.list();

		foreach(s3.Bucket s; buckets)
		{
			writeln(s.name);
		}
	}

	s3.bucket("s3utils-sample").create();

	{
		writeln("put object test");
		s3.bucket("dangar-images").put("test.txt", "test text");
	}

	{
		writeln("list object test");
		auto objectInfos = s3.bucket("dangar-images").list();

		foreach(S3.ObjectInfo info; objectInfos)
		{
			writeln("object: ", info.key);
		}
	}
}

void testPhase2()
{
	/*
	auto s3 = new S3();

	foreach(S3.Bucket bucket; s3.list())
	{
		writeln("bucket name: ", bucket.name);
		foreach(S3.Object obj; bucket.list())
		{
		}
	}
	*/
}

void main(string[] args)
{
	testPhase1();
	writeln(S3.usEast1);
}

