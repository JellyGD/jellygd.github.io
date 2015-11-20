---
layout:     post
title:      计算代码运行时间
date:       2015-11-20 10:14:20
author:     Jelly
summary:    计算代码运行时间
categories: jekyll
tags:
 - Github
 - 学习
 
---

###Objective-C 计算代码运行时间


昨天在做界面调试的时候，发现在模拟器上界面有所卡顿，以为是代码上的问题，所有做了一些时间上的比对，观察下代码的效率问题


####第一种：（最简单的NSDate）
	NSDate* tmpStartData = [NSDate date];
	//You code here...
	double deltaTime = [[NSDate date] timeIntervalSinceDate:tmpStartData];
	NSLog(@"cost time = %f", deltaTime);

####第二种：（将运行代码放入下面的Block中，返回时间）
	#import <mach/mach_time.h>  // for mach_absolute_time() and friends  
	CGFloat BNRTimeBlock (void (^block)(void)) {  
    mach_timebase_info_data_t info;  
    if (mach_timebase_info(&info) != KERN_SUCCESS) return -1.0;  
  
    	uint64_t start = mach_absolute_time ();  
    	block ();  
    	uint64_t end = mach_absolute_time ();  
    	uint64_t elapsed = end - start;  
  
    	uint64_t nanos = elapsed * info.numer / info.denom;  
    	return (CGFloat)nanos / NSEC_PER_SEC;  
	}

------
总结：在调试界面的时候，最好使用真机来进行调试，模拟器上跟真机存在差异。

BTW：TableView的一个小疑问：

	[tableView dequeueReusableCellWithIdentifier:kCellIdentifier forIndexPath:indexPath];
	
	[tableView dequeueReusableCellWithIdentifier:kCellIdentifier];
	
这两个的区别在与哪里？ 

    [tableView dequeueReusableCellWithIdentifier:kCellIdentifier forIndexPath:indexPath];
    
    需要跟
    [tableView registerClass:[DemoCell class] forCellReuseIdentifier:kCellIdentifier]; 
    或者
    [tableView registerNib:[UINib nibWithNibName:@"DemoCell" bundle:nil] kCellIdentifier];
    一起使用
    
	dequeueReusableCellWithIdentifier: forIndexPath 能够保证得到的Cell是一定不为nil
	
	而[tableView dequeueReusableCellWithIdentifier:kCellIdentifier];
	需要判断Cell 是否为空，如果为空则需要自己生成Cell
	