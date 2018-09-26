#  属性
介绍什么是属性，属性Property 可以分成多少种。

**`property`**  

`property`相当于 `ivar`(成员变量) + `getter` + `Setter` （存取方法）


--

#property属性关键字

1. 原子性 - nonatomic 特质
2. 读写权限 - readwrite (默认 ->读写)/ readonly （只读）
3. 内存管理 - assign ，strong ， weak ，unsafe_unretained ,copy
4. 存取管理  - getter=<name>,setter=<name>
5. 不常用 - nonnull（是否可为空），null_resettable，nullable  iOS9 新增关键字。


#属性介绍

>readwrite 读写权限， 会生成getter 和 setter。

>readonly 只读权限， 只会生成getter 不会生成setter。

>nonatomic 原子性，在多线程中，当前属性的操作是否安全的。 atomic代表当前属性在多线程中操作是安全的， 但是比较消耗性能，一般默认nonatomic

>retain（MRC）/strong （ARC）表示持有特性，setter方法将传入参数先保留，再赋值，传入参数的retainCount + 1；

>assign 赋值特性，setter方法将传入的参数赋值给实例变量，仅设置变量是，assign 一般用来修饰基本数据类型。

>copy 拷贝特性， 在setter中会对传入的参数复制一份，需要完全一份完全新的变量。 如果可变数组，NSMutableArray/NSMutableString 等可变对象，会变成不可变。



# 属性跟修饰符关系

| 属性声明的属性|所有权修饰符 |
|---|---|
|assign | `__unsafe_unretained `修饰符 |
|copy |__strong 修饰符（赋值的是被复制的对象） |
|retain |__strong 修饰符 |
|strong |__strong 修饰符|
|weak |__weak 修饰符|
|`unsafe_unretained` |`__unsafe_unretained ` 修饰符|


# strong实现原理


普通对象的创建过程

```
{
	id __strong obj = [[NSObject alloc] init];
}
//Clang 

{
	id obj = objc_msgSend(NSObjcect,@selector(alloc));
	objc_msgSend(obj,@selector(init));
	objc_release(obj);
}
```

NSMutableArray 的创建过程：


```
{
	id __strong obj = [NSMutableArray array];
}
//Clang

{

	id obj = objc_msgSend(NSMutableArray,@selector(array));
	objc_retainAutoreleasedReturnValue(obj);
	objc_release(obj);
	
}
```

`objc_retainAutoreleasedReturnValue`函数主要用于最优化程序运行。用于自己持有对象的函数。
但只能持有已经放到了Autoreleasepool中对象的方法或者函数的返回值。

**注意** 除了 `alloc` `new` `copy` `mutableCopy`以外的方法，编译器会自动插入该函数


`objc_retainAutoreleasedReturnValue`函数 跟 `objc_releaseReturnValue`函数一般是成对存在的。

```
+ (id)array{
	id obj = [[NSMutableArray alloc] init];
	return obj;
}	
//转换后代码

+ (id)array{
	id obj = objc_msgSend(NSMutablaArray,@selector(alloc));
	objc_msgSend(obj,@selector(init));
	return objc_releaseReturnValue(obj);
}

```

这样做的好处是：

减少对象注册到autoreleasepool中。在返回 `objc_releaseReturnValue(obj)` 的时候，会检查使用函数方法或者函数调用的执行命令列表，如果方法或函数的调用方在调用了方法或者函数后就调用`objc_retainAutoreleasedReturnValue(obj)`函数， 那么就不将返回的对象注册到autoreleasepool中，而是直接传递方法或者函数的调用方。

## 注意：

**ARC**对对象的优化

在使用非alloc new copy mutablecopy 开头生成的对象的方法，会做一个性能上的优化，避免频繁的调用 Autorelease 和 retain 方法。

没有优化之前的效果

```

+ (id)array{
	return [[NSMutableArray alloc] init];
}

// 相当于
+ (id)array{
	NSMutableArray *array = [[NSMutablearray alloc] init];
	return array;
}

// 在MRC的环境下相当于
+ (id)array{
	NSMutableArray *array = [[NSMutablearray alloc] init];
	return [array autorelease];
}

// 外部使用

id obj = [NSMutableArray array];

// 相当于


id __strong obj =  [NSMutableArray array];

// 在MRC环境下相当于

id tmp = [NSMutableArray array];

id obj = [tmp retain];

```

根据上面的情况可以得出：在`MRC`的环境下，其实得到一个对象做了一个加入AutoreleasePool 和 retain的操作。

在`ARC` 的情况下， 对此类型的方法做了优化 通过 `obj_autoleaseReturnValue()` 和 `obj_retainAutoreleaseReturnValue()` 两个方法。


`obj_autoleaseReturnValue(obj)` 会检测稍后的代码中是否有 `obj_retainAutoreleaseReturnValue(obj)`的方法，如果有，则直接返回对象。

看下伪代码的实现

```
// obj_autoreleaseReturnValue(obj)

id obj_autoleaseReturnValue(obj){
	if ( // 调用者将会执行retain ){
		set_flag(obj);
		return obj;
	}else{
		return [obj autorelease];
	}
}

id obj_retainAUtoreleaseReturnValue(obj){
	if(get_flag(obj)){
		clear_flag(obj);
		return obj;
	}else{
		return [obj retain];
	}
}

```

# weak实现的原理

__weak 变量有两个功能：

1. 若符有__weak修饰符的变量所引用的对象被废弃，则将nil赋值给变量
2. 使用__weak修饰符的变量，即是使用注册到autoreleasepool中的对象

```
{    id __weak obj1 = obj;    }

/*模拟器的模拟代码*/
id obj1;
// 初始化附有__weak修饰符的变量，初始化为0
objc_initWeak(&obj1,obj);
// 当obj1作用域结束后，调用objc_destroyWeak函数释放该变量
objc_destroyWeak(&obj1);



objc_initWeak，将obj1 = 0，调用
objc_storeWeak(&obj1,obj) 
该函数，如果第二个参数不为0，那么以key = obj地址,
value = obj1变量的地址，注册到weak表中

objc_destroyWeak(&obj1)会去调用objc_storeWeak函数，不过第二个参数为0
objc_storeWeak(&obj1,0)，把变量objc1的地址从weak表中删除


```

> **weak**修饰的对象会在对象初始化的时候，runtime 会创建一个 weak 引用表。
> weak弱应用表是一个hash表，对象的地址为key，weak指针地址数组为Value。
> 

## 对象释放后，weak对象会变成nil 过程

1. 从weak表中获取废弃对象的地址为key的记录
1. 将包含在记录中的所有附有__weak修饰符的地址，赋值为nil
1. 从weak表中删除该纪录。
1. 从引用计数表中删除废弃对象的地址为key的纪录


