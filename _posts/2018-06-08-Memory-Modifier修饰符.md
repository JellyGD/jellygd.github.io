---
layout:     post
title:      内存方面 修饰符
date:       2018-06-08
author:     Jelly
summary:    内存方面 修饰符
categories: 内存
 
---

---
# 修饰符
属性修饰符有哪些？ 

ARC 的属性修饰符

1. `__strong` 修饰符 
2. `__weak` 修饰符
3. `__unsafe_unretained` 修饰符
4. `__autoleasing` 修饰符


**注意**
如果对象超出作用域的时候，对象的释放是不定的。

--
# `__strong` 修饰符

> `__strong` 修饰符是 id类型 和 对象类型默认的所有权修饰符。
> 
> `__strong` 修饰符表示对对象的“强引用”。
> 
> 持有强引用的变量在超出其作用域时被废弃，随之强引用失效，引用的对象会随之释放。



```
id objc = [[Object alloc] init];

//相当于 在id类型或者对象类型没有明确所有权修饰符的时候，系统会默认添加__strong 修饰符。

id __strong objc = [[Object alloc] init];

```
--
# `__weak`修饰符

`__weak` 修饰符 主要是为了解决循环引用而引入的修饰符。 `__weak` 修饰符跟 `__strong`修饰符刚好相反，提供弱引用。
弱引用不能持有对象的实例。`__weak`修饰符在该对象被废弃的时候，弱引用会自动失效，并会赋值为nil。 （空弱引用）。

> 循环引用 是指对象之间互相引用，强持有对象，导致对象的`retainCount`一直不为0， 从而导致对象无法释放。
> 
> 相互引用包括，A->B,B->A | A->A | A->B,B->C,C->A | 多种情况的引用。
> 
> 循环引用容易发送内存泄露的问题，就是在应当废弃的对象在超出其生命周期后继续存在。
> 

```
id __weak obj1 = nil;
{
    id obj = [[NSObject alloc] init];
    obj1 = obj;
    NSLog(@"A : %@",obj);
}
NSLog(@"B : %@",obj1);
```  

--
# `__unsafe_unretained` 修饰符

`_weak` 修饰符在iOS5 以上才提供的， 在iOS4的应用程序中可使用 `__unsfe_unretained`修饰符

`__unsafe_unretained`修饰符主要在于`__unsafe`表示不安全的所有权修饰符。

`__unsafe_unretained`修饰的变量不属于编译器内存管理对象。


```
	id __unsafe_unretained obj = [[NSObject alloc] init];
	
	//在obj 被释放的时候， 在对obj进行访问的话， 会造成错误的地址访问。
```


```
id __unsafe_unretained obj1 = nil;
{
   id obj = [[NSObject alloc] init];
   obj1 = obj;
   NSLog(@"A : %@",obj);
}
NSLog(@"B : %@",obj1);

```

**注意**

在使用`__unsafe_unretained`修饰符修饰的对象的时候，赋值给__strong修饰符的变量的时候，**必须**要确保被赋值对象的存在。

--

# `__autoreleasing`修饰符

在 ARC 环境下，不能使用 `autolease`方法 和 `NSAutoleasePool`类。 但是`autolease` 功能是起作用的。

```
//ARC 环境下：
@autoleasepool{
	id __autoreleasing obj = [[NSObject alloc] init];
}
	
```
通过使用`autoleasepool`块 来代替`NSAutoreleasePool`类对象生成，持有以及废弃。

**注意！！！**

`init`方法返回值的对象不注册到`autoreleasepool` 中。 编译器会检查方法名是否以 `alloc`/`new`/`copy`/`mutableCopy`开始，如果不是则自动将返回值的对象注册到`autoreleasepool`中。

由于`return`使得对象变量超出其作用域，所以强引用对应的自己持有的对象会被自动释放，但该对象座位函数的**返回值**，编译器会**自动**将其注册到`autoreleasepool`中。

--

> 在访问附有 __weak 修饰符的变量时，必定要访问注册到 `autoreleapool`的对象
> 
> 因为 `__weak`修饰符只持有对象的弱引用，而在访问引用对象的过程中，该对象可能被废弃，
> 

id的指针或者对象的指针在没有显示的修饰符的时候，会被附上`__autoreleasing`修饰符。




