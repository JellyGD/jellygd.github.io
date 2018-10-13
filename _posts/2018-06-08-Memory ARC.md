---
layout:     post
title:      内存方面 ARC介绍
date:       2018-06-08
author:     Jelly
summary:    内存方面 ARC介绍
categories: 内存
 
---
---
#  ARC 介绍原理
!!内存管理的原则
   
1.  自己生成的对象，自己持有
2.  非自己生成的对象，自己也能持有
3.  不再需要自己持有的对象时释放
4.  非自己持有的对象无法释放



*对象操作与Objective-C方法的对应*

|对象操作 | Objective-C 方法|
|---|---|
|生成持有对象 | alloc / new / copy / MutableCopy等方法|
|持有对象 | retain 方法 |
|释放对象 | release 方法|
|废弃对象 | dealloc 方法|

## 1.自己生成的对象，自己持有

>使用NSObject 类的alloc 类方法 自己生成对象并持有。

```
id objc = [[NSObject alloc] init];
	
//相当于
id objc1 = [NSObject new];
	
//自己创建并持有对象。
```
### copy && mutableCopy

>copy 方法利用基于 NSCopying 方法约定， 有各类实现的 copyWithZone: 方法生成并持有对象的副本。 （***原型模式***）
>
> mutableCopy 方法利用基于 NSMutableCopy 方法约定，生成可变的对象。


## 2.非自己生成的对象，自己也能持有

> 通过retain 方法，非自己生成的对象，自己也能持有。
	
```
id obj = [NSMutableArray array];
//取得的对象存在，但自己不持有对象
[obj retain];
//自己持有对象
```

## 3.不在需要自己持有的对象时 释放。
	
	自己持有的对象，一旦不需要，持有者有义务有对象释放该对象。 通过release 方法。
		
```
id obj = [NSMutableArray array];
//自己持有对象。
[obj retain];
//释放对象， 对象将不可以访问
[obj release];

```

## 4.非自己持有的对象无法释放。

分成两种情况

> 1. 自己持有的对象释放后变成非自己持有的对象， 再次释放
> 2. 非自己生成的对象， 自己没有持有，调用释放

### 过度释放问题。

```
//生成并持有对象
id obj = [[NSObject alloc] init]; 
//对象被释放
[obj release];
//再次调用对象释放
[obj release];



/**
自己持有的对象释放后，已非自己持有的对象！！
再次释放会造成应用程序奔溃。

再度废弃已经废弃了的对象是崩溃， 
访问已经废弃的对象时奔溃。
*/
```

##### 释放非自己持有的对象

```
id objc1 = [objc Object];

[objc1  release]; 
/**
释放非自己持有的对象必定导致程序奔溃。 
*/
```



#### Object 创建的过程

```

+ alloc
+ allocWithZone
class_createInstance 
calloc

```

retainCount retain release 

> 苹果是通过散列表（引用计数表）来管理引用计数
>
> 通过引用计数表管理引用计数器的好处 （对比与放在内存头部）：
>
> 1.对象用内存块的分配无需考虑内存块头部。
>
> 2.引用技术表个记录中存有内存地址，可以从各个记录追溯到个对象的内存块。 

```
- (NSUInteger)retainCount{
	return (NSUInteger)__CFDoExternRefOperation(OPERATION_retainCount,self);
}

- (id)retain{
	return (id)__CFDoExternRefOperation(OPERATION_retain,self);
}

- (void)release{
	__CFDoExternRefOperation(OPERATION_release,self);
}

```



## 重点 autorelease

> autorelease 自动释放， 类似C语言中 自动变量（局部变量）的特性。
> 
> 当对象超出其作用域时，对象实例的 release 实例方法被调用
> 
> 在对象后面添加Autolease 相当于在 调用 [atuleasePool addObject:self];


**autolease**的使用方法：

> 1.生成并持有NSAutoreleasePool 对象；
> 
> 2.调用已分配对象的 autolease 实例方法；
> 
> 3.废弃 NSAutoreleasPool 对象。


```
/**
NSAutoreleasePool 的生命周期相当于 C 语言的变量的作用域。
在 自动释放中通过autolease 添加的对象，在NSAutoleasePool 废弃的时候，
都会调用 Object 的relase 方法。
*/
NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

id obj = [[Object alloc] init];

[obj autolease];

[pool drain];

```

**注意**

在Cocoa框架中，**NSAutorelasePool**是依赖于**NSRunLoop**的， 管理这Pool的**生成，持有和废弃**处理。
	
问题，在使用**大量**的Autolrease的对象时，只要 AutoleasePool 不被释放，那么生成的对象是不会被释放的。过多的话，会出现**内存不足**的现象。
	
解决当前这个问题，**有必要在适当的地方**生成，持有和废弃**NSAutoreleasePool**对象。


```
for (NSInteger i = 0; i < 图像数 ; i++ ){
	NSAutolreasePool *pool = [[NSAutoreleasePool alloc] init];
	
	//读取图片
	
	[pool drain];
}

```

在Cocoa框架中， 系统提供的很多类方法返回的对象，会自动添加autolrease。

```
	id array = [NSMutableArray array];
	//相当于
	id array = [[[NSMutableArray alloc] initArray] autolease];
	
```

如果对**NSAutoleasePool** 调用 **autolease** 方法，会发生**异常**， 表明不能自动释放一个自动释放池 

Cannot autolease an autolease pool。

NSAutoleasePool的autolease 方法被改类重载。




## ARC规则 

在ARC有效的情况下，编译源码必须遵守一定的规则。

1. 不能使用`retain`/`release`/`retainCount`/`autorelease`;

2. 不能使用 `NSAllocateObject` / `NSDeallocateObject`

3. 必须遵守内存管理的方法命名规则。
 
4. 不能显示的调用`dealloc`

5. 使用`@autoreleasepool`块来代替`NSAutoreleasePool`

6. 不能使用区域`NSZone`

7. 对象型变量不能作为C语言结构体（`struct`/`union`）的成员

8. 显示转换 `id` 和 `void *`；


---
**注意！！！！**

必须遵守内存管理的方法命名规则。

以 `alloc` `new` `copy` `mutablecopy` `init` 名称开始的方法，在返回对象是，必须返回调用方所应当持有的对象。

`init` 方法必须是对象的实例方法，必须要返回对象。 返回的对象应当为 `id`类型或者改方法声明类的对象类型，或者是该对象类的超类或子类。
`init`方法返回的对象并不注册到 `autoleasepool`中。 基本上只是对 `alloc` 方法返回值的对象进行初始化处理并返回对象。


