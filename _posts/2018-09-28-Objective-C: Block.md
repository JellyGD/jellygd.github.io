# Block的声明以及使用
block 顾名思义代码块，将同一逻辑的代码放在一块，方便维护和代码更加简洁紧凑，易于阅读,而且它比函数使用更方便，代码更美观.
block属性声明使用的是修饰符是copy，至于为什么会是copy接下来会讨论。本章会从简单的使用block，然后抽丝剥茧慢慢的深挖block的原理，知道了原理之后，才能够准确的判断问题和在开发中完善代码不会出坑。

## block 的定义
简单的使用block，可以先从block的定义来查看。

``` objc

	返回类型(^block名称)(形参列表) = ^(形参列表){
	
	};

```
来看看block的调用时如何调用的

``` objc

	block名称(实参); // 简单快捷
	
	// 一般我们定义block 都是当成property来使用的， 也有直接把block 当成参数来传递的。

```

可以通过`typedef <#returnType#>(^<#name#>)(<#arguments#>);` 来定义block。 可以看出 `returnType `是返回类型，`name `是block的名称，`arguments `则是形参列表，那么简单的使用则如下：

``` objc
xxx.m

typedef void(^BlockName)(NSString *name); // 一般如果形参列表没有，则写 void， 否则会有编译警告

@property (nonatomic, copy) BlockName block; // 定义block属性。内存属性修饰符copy

// 调用block 则简单很多

if (self.block) { // 判断block 是否存在，存在才调用
	self.block(@"hello word");
}

// 外部可以对block进行赋值。

__weaktypeof(self) weakSelf = self; // 当前使用到了 weakself，接下来也会讲到，是用来解决循环引用问题的。
self.xxx.block = ^(NSString *name){
	weakSelf.titleLabel.text = name;
};

```

Block的使用，是不是很简单。 那么接下来复杂一点，带返回值的block；

``` objc
typedef (NSString *)(^BlockName)(NSString *name); // 当前定义了一个返回值为NSString的BlockName的block。

@property (nonatomic, copy) BlockName block; // 定义block属性。内存属性修饰符copy

// 调用block 则简单很多

if (self.block) { // 判断block 是否存在，存在才调用
	NSString *name = self.block(@"hello word");
	console.log(@"%@", name);
}

// 外部可以对block进行赋值。

self.xxx.block = ^(NSString *name){
	return [NSString stringWithFormat:@"返回值 %@",name];
};

// 结果打印 返回值 hello word

```

带返回值的Block 也很简单对不对。 好了， 来个666的操作来一波哈~~  

``` objc
GDBlockDemo.h

@interface GDBlockDemo : NSObject

@property (nonatomic, assign) NSInteger totalNum;

- (GDBlockDemo *(^)(NSUInteger num))addNum;

@end


GDBlockDemo.m

#import "GDBlockDemo.h"

@implementation GDBlockDemo

- (GDBlockDemo *(^)(NSUInteger num))addNum{
    return ^(NSUInteger num){
        self.totalNum += num;
        return self;
    };
}


@end

GDBlockDemo *gdDemo = [[GDBlockDemo alloc] init];
gdDemo.addNum(1).addNum(2).addNum(3);

```
这一波操作如何？ 看懂了没有呢？  这个叫**链式编程**哈~~~  链式编程这里不多讲， 有兴趣的可以跟我说哈~~

装逼装完了， 开始了解下原理性的东西了~~ 

## block的内存属性为什么是copy，能其他的吗？
那么内存属性是copy，肯定就要说下内存方面了，block在内存中是存放在什么位置呢? 接下来我们来查看下block存储的位置。

``` objc
- (void)showBlockAddress{
    
    void(^block1)(void) = ^(){
        NSLog(@"block1");
    };
    NSLog(@"block1, %@",block1);
    
    NSUInteger index = 1;
    void(^block2)(void) = ^(){
        NSLog(@"block2 %lu",(unsigned long)index);
    };
    NSLog(@"block2, %@",block2);
    
    __block NSUInteger index2 = 1;
    void(^block3)(void) = ^(){
        index2 = 3;
    };
    NSLog(@"block3, %@",block3);
}

```

输入结果如下：

``` objc
2018-09-28 02:04:20.543496+0800 Network[44601:1212691] block1, <__NSGlobalBlock__: 0x1075afb08>
2018-09-28 02:04:20.543661+0800 Network[44601:1212691] block2, <__NSMallocBlock__: 0x6000007e8930>
2018-09-28 02:04:20.543806+0800 Network[44601:1212691] block3, <__NSMallocBlock__: 0x6000007e5980>
```
可以看出第一个block 在全局区域，第二个跟第三个在堆区域中。 其实还有一个block的类型是在栈区域中的。

Block在内存中的位置分为三种类型`NSGlobalBlock`，`NSStackBlock`, `NSMallocBlock`。

	NSGlobalBlock：类似函数，位于text段；
	NSStackBlock：位于栈内存，函数返回后Block将无效；
	NSMallocBlock：位于堆内存。
	
`NSGlobalBlock `是block中没有引用外部变量的。

`NSStackBlock ` 是block在MRC的情况下 创建的block是放在栈区域的。 

`NSMallocBlock ` 是block在ARC的情况下，默认会将block从栈中复制到堆中，而MRC 需要手动的copy到堆中。

所以根据以上的情况，如果在ARC的情况下，property的内存修饰符是可以使用strong的，为什么一直惯用copy的原因，猜测只是保留了原有的习惯和告诉自己block是从栈中复制到堆中的。

## block是如何捕获值的呢？
block的定义是 带有自动变量值的匿名函数。  带有自动变量值说的就是截获自动变量值。

``` objc
#import <Foundation/Foundation.h>

- (void)testBlock {
    int val = 10;
    const char *fmt = "val = %d\n";
    void (^block)(void) = ^(){
        printf(fmt,val);
    };
    val = 100;
    fmt = "val已经改变 = %d\n";
    block();
    
}

```
上一句的代码的输出结果是

`val = 10`

执行的结果并不是`val已经改变 = 100`，而是执行block语法时自动变量的瞬间值，因为这些值（fmt`val = %d\n` ,val`10`）被保存（截获），从而在执行块中使用。 


### __block说明符的作用
自动变量值被截获只能保存执行Block语法的瞬间值，保存后就不能改写改值。在之前的代码中，也看到了使用了`__block`来修饰变量，然后在`block`中就可以当前的变量做修改。如果不加`__block`则只能对变量做引用。 

如果不加block 是不是全部都不能修改呢？ 来看下接下来的代码 有没有问题？ 

``` objc

- (void)testBlockArray{
    NSMutableArray *array = [NSMutableArray array];
    void (^block)(void) = ^(){
        NSObject *obj = [[NSObject alloc] init];
        [array addObject:obj];
        NSLog(@"block array = %@",array);
    };
    NSLog(@"array = %@",array);
    block();
    NSLog(@"array block end= %@",array);
}

```

block是会自动截获变量， 但是截获的是类对象的结构体实例指针。 

**注意**

block截获自动变量的方法并没有实现对C语言数组的截获。


## block的原理是什么？
block通过支持block的编译器，含有Block语法的源代码转换为一般C语言编译器能够处理的源代码。并做为C语言的源代码被编译。

``` objc

struct __block_impl {
    void *isa; // 指向所属类的指针，也就是block的类型
    int Flags; // 标志变量，在实现block的内部操作时会用到
    int Reserved; // 保留变量
    void *FuncPtr; // block执行时调用的函数指针
};
// Runtime copy/destroy helper functions (from Block_private.h)

struct __BlockSImple__simpleGD_block_impl_0 {
    struct __block_impl impl; // block的结构体
    struct __BlockSImple__simpleGD_block_desc_0* Desc; // 内存相关 开辟内存控件的大小
    // 结构体构造函数
    __BlockSImple__simpleGD_block_impl_0(void *fp, struct __BlockSImple__simpleGD_block_desc_0 *desc, int flags=0) {
        impl.isa = &_NSConcreteStackBlock; // Block 生成是在栈上的。
        impl.Flags = flags;
        impl.FuncPtr = fp;
        Desc = desc;
    }
};
// 方法的真正操作的位置。
static void __BlockSImple__simpleGD_block_func_0(struct __BlockSImple__simpleGD_block_impl_0 *__cself) {
    printf("block"); }

static struct __BlockSImple__simpleGD_block_desc_0 {
    size_t reserved; // 内存区域
    size_t Block_size; // 大小
} __BlockSImple__simpleGD_block_desc_0_DATA = { 0, sizeof(struct __BlockSImple__simpleGD_block_impl_0)};

static void _I_BlockSImple_simpleGD(BlockSImple * self, SEL _cmd) {
    // 定义Block
    void (*blk)(void) = ((void (*)())&__BlockSImple__simpleGD_block_impl_0((void *)__BlockSImple__simpleGD_block_func_0, &__BlockSImple__simpleGD_block_desc_0_DATA));
    // 执行Block
    ((void (*)(__block_impl *))((__block_impl *)blk)->FuncPtr)((__block_impl *)blk);

     // 简化下
    struct __BlockSImple__simpleGD_block_impl_0 tmp = __BlockSImple__simpleGD_block_impl_0(__BlockSImple__simpleGD_block_func_0,&__BlockSImple__simpleGD_block_desc_0_DATA);
    /*
     * __BlockSImple__simpleGD_block_impl_0 通过构造函数 可以得知
     * impl.FuncPtr = __BlockSImple__simpleGD_block_func_0;
     * Desc = &__BlockSImple__simpleGD_block_desc_0_DATA;
     */
     
    struct__BlockSImple__simpleGD_block_impl_0 *blk = &tmp;
    
    (*blk -> impl.FuncPtr)(blk); // 函数指针调用函数
}


```
clang后，再对代码进行简化，可以看出会比较简单。 主要来说， 是数据怎么去做截获的。 

先给个结论：**在执行Block语法时，Block语法表达式锁使用的自动变量值被保存到Block的结构体实例中。**

接下来看下`clang`下简单的代码：

``` objc
NSUInteger index = 1;
void(^block2)(void) = ^(){
    NSLog(@"block2 %lu",(unsigned long)index);
};
    
```
clang后得到的简化代码如下：

``` objcs
struct __BlockSImple__simpleGD_block_impl_0 {
  struct __block_impl impl;
  struct __BlockSImple__simpleGD_block_desc_0* Desc;
  NSUInteger index;
  __BlockSImple__simpleGD_block_impl_0(void *fp, struct __BlockSImple__simpleGD_block_desc_0 *desc, NSUInteger _index, int flags=0) : index(_index) {
    impl.isa = &_NSConcreteStackBlock;
    impl.Flags = flags;
    impl.FuncPtr = fp;
    Desc = desc;
  }
};
static void __BlockSImple__simpleGD_block_func_0(struct __BlockSImple__simpleGD_block_impl_0 *__cself) {
  NSUInteger index = __cself->index; // bound by copy

        NSLog((NSString *)&__NSConstantStringImpl__var_folders_73_qvvgqbjs293gvcwl1xmjc01m0000gp_T_BlockSImple_f505ff_mi_0,(unsigned long)index);
    }

static struct __BlockSImple__simpleGD_block_desc_0 {
  size_t reserved;
  size_t Block_size;
} __BlockSImple__simpleGD_block_desc_0_DATA = { 0, sizeof(struct __BlockSImple__simpleGD_block_impl_0)};

static void _I_BlockSImple_simpleGD(BlockSImple * self, SEL _cmd) {
    NSUInteger index = 1;
    void(*block2)(void) = ((void (*)())&__BlockSImple__simpleGD_block_impl_0((void *)__BlockSImple__simpleGD_block_func_0, &__BlockSImple__simpleGD_block_desc_0_DATA, index));
}

```


可以看出 在`__BlockSImple__simpleGD_block_impl_0 `结构体中增加了 ` NSUInteger index;`, 在构造函数中增加了 `: index(_index)`。

就是在block 声明的时候，就已经把当前值已经存储到了block的结构体实例中。 

**当前值** 这个跟 对象在内存中表现有关  **地址 : 值**。  我们传递的是值而不是对象地址。 所以不能对对象地址进行新的赋值， 但是可以对值进行操作, 也就出现了 之前的代码 NSMutableArray 可以往数组里面添加对象。

接下来看下 __block 修饰符。 这个会对block的结构体有什么改变。

``` objc
struct __Block_byref_array_0 {
  void *__isa; // 对象的实现
__Block_byref_array_0 *__forwarding; // 指向自身的指针。
 int __flags;
 int __size;

 void (*__Block_byref_id_object_copy)(void*, void*); // 对象类型才有 copy的方法  当Block从栈复制到堆时，使用_Block_object_copy函数，持有Block截获的对象
 void (*__Block_byref_id_object_dispose)(void*); // 对象类型才有dispose方法 当堆上的Block被废弃时，使用_Block_object_dispose函数，释放Block截获的对象。
 NSMutableArray *array; // __block变量被追加为成员变量 ARC 上 默认是Strong的。
};

struct __BlockClass__testBlock1Array_block_impl_0 {
  struct __block_impl impl;
  struct __BlockClass__testBlock1Array_block_desc_0* Desc;
  __Block_byref_array_0 *array; // by ref 多了一个结构体
  __BlockClass__testBlock1Array_block_impl_0(void *fp, struct __BlockClass__testBlock1Array_block_desc_0 *desc, __Block_byref_array_0 *_array, int flags=0) : array(_array->__forwarding) {
    impl.isa = &_NSConcreteStackBlock;
    impl.Flags = flags;
    impl.FuncPtr = fp;
    Desc = desc;
  }
};
static void __BlockClass__testBlock1Array_block_func_0(struct __BlockClass__testBlock1Array_block_impl_0 *__cself) {
  __Block_byref_array_0 *array = __cself->array; // bound by ref

        (array->__forwarding->array) = ((NSMutableArray * _Nonnull (*)(id, SEL))(void *)objc_msgSend)((id)objc_getClass("NSMutableArray"), sel_registerName("array"));
        ((void (*)(id, SEL, ObjectType _Nonnull))(void *)objc_msgSend)((id)(array->__forwarding->array), sel_registerName("addObject:"), (id _Nonnull)(NSString *)&__NSConstantStringImpl__var_folders_73_qvvgqbjs293gvcwl1xmjc01m0000gp_T_BlockClass_a8ebec_mi_1);
        NSLog((NSString *)&__NSConstantStringImpl__var_folders_73_qvvgqbjs293gvcwl1xmjc01m0000gp_T_BlockClass_a8ebec_mi_2,(array->__forwarding->array), (array->__forwarding->array));

    }
static void __BlockClass__testBlock1Array_block_copy_0(struct __BlockClass__testBlock1Array_block_impl_0*dst, struct __BlockClass__testBlock1Array_block_impl_0*src) {_Block_object_assign((void*)&dst->array, (void*)src->array, 8/*BLOCK_FIELD_IS_BYREF*/);}

static void __BlockClass__testBlock1Array_block_dispose_0(struct __BlockClass__testBlock1Array_block_impl_0*src) {_Block_object_dispose((void*)src->array, 8/*BLOCK_FIELD_IS_BYREF*/);}

static struct __BlockClass__testBlock1Array_block_desc_0 {
  size_t reserved;
  size_t Block_size;
  void (*copy)(struct __BlockClass__testBlock1Array_block_impl_0*, struct __BlockClass__testBlock1Array_block_impl_0*);
  void (*dispose)(struct __BlockClass__testBlock1Array_block_impl_0*);
} __BlockClass__testBlock1Array_block_desc_0_DATA = { 0, sizeof(struct __BlockClass__testBlock1Array_block_impl_0), __BlockClass__testBlock1Array_block_copy_0, __BlockClass__testBlock1Array_block_dispose_0};

static void _I_BlockClass_testBlock1Array(BlockClass * self, SEL _cmd) {
    __attribute__((__blocks__(byref))) __Block_byref_array_0 array = {(void*)0,(__Block_byref_array_0 *)&array, 33554432, sizeof(__Block_byref_array_0), __Block_byref_id_object_copy_131, __Block_byref_id_object_dispose_131, ((NSMutableArray * _Nonnull (*)(id, SEL))(void *)objc_msgSend)((id)objc_getClass("NSMutableArray"), sel_registerName("array"))};
    ((void (*)(id, SEL, ObjectType _Nonnull))(void *)objc_msgSend)((id)(array.__forwarding->array), sel_registerName("addObject:"), (id _Nonnull)(NSString *)&__NSConstantStringImpl__var_folders_73_qvvgqbjs293gvcwl1xmjc01m0000gp_T_BlockClass_a8ebec_mi_0);
    void (*block)(void) = ((void (*)())&__BlockClass__testBlock1Array_block_impl_0((void *)__BlockClass__testBlock1Array_block_func_0, &__BlockClass__testBlock1Array_block_desc_0_DATA, (__Block_byref_array_0 *)&array, 570425344));

    NSLog((NSString *)&__NSConstantStringImpl__var_folders_73_qvvgqbjs293gvcwl1xmjc01m0000gp_T_BlockClass_a8ebec_mi_3,(array.__forwarding->array), (array.__forwarding->array));
    ((void (*)(__block_impl *))((__block_impl *)block)->FuncPtr)((__block_impl *)block);
    NSLog((NSString *)&__NSConstantStringImpl__var_folders_73_qvvgqbjs293gvcwl1xmjc01m0000gp_T_BlockClass_a8ebec_mi_4,(array.__forwarding->array), (array.__forwarding->array));

}
```

相对于不加`__block 修饰符`，`clang`后的代码多了`__Block_byref_array_0 `结构体
在 array 初始化的时候， 就已经变成下面的代码的样子， 得到的是 `__Block_byref_array_0` 结构体实例。

**注意**

里面有两个函数 `_Block_object_assign ` 和`_Block_object_dispose `两个函数。

`_Block_object_assign ` 函数相当于 `retain`实例方法的函数， 将对象赋值在对象类型的结构体成员变量中。

`_Block_object_dispose `函数相当于 释放block中结构体实例中的成员变量。

来看看，转换后的 `NSMutableArray` 是什么？ 

``` objc
__attribute__((__blocks__(byref))) __Block_byref_array_0 array = {(void*)0,(__Block_byref_array_0 *)&array, 33554432, sizeof(__Block_byref_array_0), __Block_byref_id_object_copy_131, __Block_byref_id_object_dispose_131, ((NSMutableArray * _Nonnull (*)(id, SEL))(void *)objc_msgSend)((id)objc_getClass("NSMutableArray"), sel_registerName("array"))};

// 将得到的array 转换成 __Block_byref_array_0 的结构体

struct __Block_byref_array_0 {
  void *__isa; // 对象的实现
__Block_byref_array_0 *__forwarding; // 指向自身的指针。
 int __flags;
 int __size;

 void (*__Block_byref_id_object_copy)(void*, void*); // 对象类型才有 copy的方法  当Block从栈复制到堆时，使用_Block_object_copy函数，持有Block截获的对象
 void (*__Block_byref_id_object_dispose)(void*); // 对象类型才有dispose方法 当堆上的Block被废弃时，使用_Block_object_dispose函数，释放Block截获的对象。
 NSMutableArray *array; // __block变量被追加为成员变量 ARC 上 默认是Strong的, 也就是Block 会持有object的原因。
};

```

在接下来调用 array的 使用方式变成了： `array->__forwarding->array`

	array （第一个）： 结构体（__Block_byref_array_0）的指针。
	__forwarding ：  指向自身的指针。 会根据 block从栈中拷贝到堆中， 指向地址也会跟随着变化 指向堆中的对象地址。
	array （第二个）： 结构体中保存的成员变量。 
	
**注意**

`__Block_byref_array_0 ` 结构体不写到block的结构体中的原因， 是为了防止其他的block 也使用当前 array 。 这样就可以减少代码量和空间。

在ARC 有效的情况下， 编译器会判断将自动生成的Block 从栈中拷贝到堆中的代码，因此不需要自己手动的拷贝block 到堆中，而MRC则需要。



##  block中遇到循环引用怎么解决？ 

首先先了解下， 什么时候循环引用，（retain cycle）。

Object 决定是否会被释放的条件是 retainCount(引用计数器) 为 0; 在对Object持有操作的时候（strong,retain,copy），会对对象的引用计数器加1，从而让Object对象不会被释放。

根据这种情况，如果对象A持有对象B， 对象B 间接或直接的 持有对象A， 形成了一个引用环。 B的释放需要等待持有对象A调用release， 对象A又在等待着独享B的release 方法调用。 所以导致对象A 和 对象B 一直不释放。

那么在Block为什么会有循环引用呢？ 

``` objc
typedef void(^block1)(void);

@interface GDBlockDemo : NSObject	

@property (nonatomic, copy) block1 block;

@end

// 使用的时候
@implementation GDBlockDemo

- (void)configBlock{
    self.block = ^(){
        [self doSomething];
    };
}

@end
	
```

上面的代码中，在 `configBlock `函数中， 为`block` 赋值， 但是这个时候，`block`会对`self`做持有的操作， 而`self`自身也持有着`block`。 导致出现了环。 从而引起内存泄露。 

那么如何解决循环引用的问题呢？  需要对上面的代码做如下修改：

``` objc
- (void)configBlock{
    __weak typedef(self) weakSelf = self;
    self.block = ^(){
        [weakSelf doSomething];
    };
}
```
定义了一个新的`weak `变量 `__weak typedef(self) weakSelf = self;`
调用改成 `[weakSelf doSomething];`

### weakself 怎么实现的
直接`clang`来查看下，`__weak `怎么实现的。 

需要对clang的命令改变下：
`clang -rewrite-objc -fobjc-arc -fobjc-runtime=macosx-10.13 main.m `

-fobjc-arc代表当前是arc环境 -fobjc-runtime=macosx-10.13：代表当前运行时环境 缺一不可 clang指令，否则会出现下面的错误提示：

``` objc
error: cannot create __weak reference because the current deployment target does not support weak references
    __attribute__((objc_ownership(weak))) typeof(self) weakSelf = self;
```

``` objc

struct __BlockSImple__weakSelfDemo_block_impl_0 {
  struct __block_impl impl;
  struct __BlockSImple__weakSelfDemo_block_desc_0* Desc;
  BlockSImple *const __weak weakSelf;
  __BlockSImple__weakSelfDemo_block_impl_0(void *fp, struct __BlockSImple__weakSelfDemo_block_desc_0 *desc, BlockSImple *const __weak _weakSelf, int flags=0) : weakSelf(_weakSelf) {
    impl.isa = &_NSConcreteStackBlock;
    impl.Flags = flags;
    impl.FuncPtr = fp;
    Desc = desc;
  }
};
static void __BlockSImple__weakSelfDemo_block_func_0(struct __BlockSImple__weakSelfDemo_block_impl_0 *__cself) {
  BlockSImple *const __weak weakSelf = __cself->weakSelf; // bound by copy

        NSLog((NSString *)&__NSConstantStringImpl__var_folders_73_qvvgqbjs293gvcwl1xmjc01m0000gp_T_BlockSImple_19b9cf_mi_1,weakSelf);
    }
static void __BlockSImple__weakSelfDemo_block_copy_0(struct __BlockSImple__weakSelfDemo_block_impl_0*dst, struct __BlockSImple__weakSelfDemo_block_impl_0*src) {_Block_object_assign((void*)&dst->weakSelf, (void*)src->weakSelf, 3/*BLOCK_FIELD_IS_OBJECT*/);}

static void __BlockSImple__weakSelfDemo_block_dispose_0(struct __BlockSImple__weakSelfDemo_block_impl_0*src) {_Block_object_dispose((void*)src->weakSelf, 3/*BLOCK_FIELD_IS_OBJECT*/);}

static struct __BlockSImple__weakSelfDemo_block_desc_0 {
  size_t reserved;
  size_t Block_size;
  void (*copy)(struct __BlockSImple__weakSelfDemo_block_impl_0*, struct __BlockSImple__weakSelfDemo_block_impl_0*);
  void (*dispose)(struct __BlockSImple__weakSelfDemo_block_impl_0*);
} __BlockSImple__weakSelfDemo_block_desc_0_DATA = { 0, sizeof(struct __BlockSImple__weakSelfDemo_block_impl_0), __BlockSImple__weakSelfDemo_block_copy_0, __BlockSImple__weakSelfDemo_block_dispose_0};

static void _I_BlockSImple_weakSelfDemo(BlockSImple * self, SEL _cmd) {
    __attribute__((objc_ownership(weak))) typeof(self) weakSelf = self;
    ((void (*)(id, SEL, BlockName))(void *)objc_msgSend)((id)self, sel_registerName("setBlock:"), ((void (*)())&__BlockSImple__weakSelfDemo_block_impl_0((void *)__BlockSImple__weakSelfDemo_block_func_0, &__BlockSImple__weakSelfDemo_block_desc_0_DATA, weakSelf, 570425344)));
}

```

在结构体中 `__BlockSImple__weakSelfDemo_block_impl_0 ` 中添加了一个只读的`BlockSImple *const __weak weakSelf;`

在当前的结构体中， 定义的是 __weak 的weakSelf 这样，在Block 中是不会对self经常强持有的， 所以能够解决循环引用的问题。 


**注意**

1.不是所有的`Block`使用到`self`的都需要添加`weakself`，因为不一定会形成循环引用，例如：

```objc
[UIView animateWithDuration:0.5 animations:^{ 
	NSLog(@"%@", self);
}];
```

2. 没有使用`__block`的变量和使用`__weak typeof(xxx) ` 都没有在新生产一个`__Block_byref_xxx_0`的结构体，只有__block修饰的才会生成这样的结构体。

****



# weakself 和 strongself

weakself 刚才已经说明了， 就是针对循环引用的时候后，解决循环引用的。 

`__weak typedef(self) weakSelf = self;` 会变成Block结构体中的一个 weak成员变量。
这样block的调用就不会有循环引用了。  [根据weak的特性， 会在对象self 释放的时候自动变成nil。](http://jellygd.github.io/2018/09/26/Memory-weak%E5%AE%9E%E7%8E%B0%E8%BF%87%E7%A8%8B/) 也就是说会不安全的。 那么如果想保证block 的代码能够顺利的执行完成， 就添加了 `strongSelf` 的概念。 

```objc
- (void)weakSelfDemo{
    __weak typeof(self) weakSelf = self;
    self.block = ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(self) strongSelf = weakSelf;
            NSLog(@"%@",strongSelf);
        });
    };
}
```

`strongSelf `的作用就是对weakSelf 做强引用，保证代码的执行，执行过后，`strongSelf`就会被释放，`weakSelf`也会随之释放。



## typedef 是什么？

typeof() 函数只是返回参数的类型

#总结 

1、`__block` 修饰的外部局部变量值和引用类型，都会重新生成一个包裹变量结构体`__Block_byref_xxx_0`，当前这个结构体把变量当成成员变量，通过`forwarding`的指针来解决栈copy到堆的问题。 

2、没有修饰符的值类型和引用类型都会重新生成一个变量，值类型重新生成一个变量，将局部变量的值赋值给他，引用类型的变量，重新生成一个新指针，指向这个指针的copy，强引用。

3、`weak`修饰符，没有重新生成包裹变量的结构体，重新声明一个弱引用指针，指向这个指针的copy体，所以不可以在内部修改变量的值；只能修饰引用类型的变量，所以 weak 修饰可以防止循环引用； 


# 扩展阅读

### strong 和 copy 修饰符有什么不同？（深浅拷贝方面）

### 内存的5大区域。
内存的5大区域分别是: 

	1.栈区 （stack）: 存放函数的参数值，局部变量等，由编译器自动分配和释放，
		通常函数执行结束后就会被释放。相对于数据结构中的栈。  效率高，但是容量有限。
		
	2.堆区 （heap）： 通过 new  malloc realloc 分配的内存块，编译器不管释放，
		需要手动管理。如果应用程序没有释放，操作系统会回收。 分配方式类似数据结构中的链表。
		
	3.常量区： 常量存储地方，不允许修改。
	
	4.静态区： 全局变量和静态变量的存储是放在一块的，初始化的全局变量和静态变量在一块区域，
		未初始化的全局变量和未初始化的静态变量在相邻的另一块区域。程序结束后，由系统释放。
		
	5.代码区：存放函数体的二进制代码。

#### 堆栈的区别
	1、分配释放： 栈中的分配有编译器自动分配和释放， 对于堆来说，释放工作由程序员控制。
	
	2、空间上： 栈空间比堆空间小很多。
	
	3、生命周期：栈中存储的变量出了作用域就无效了，而堆由于是由程序员进行控制释放的，
				变量的生命周期可以延长。

## 面试题

1.下面代码执行结果是？（ARC的情况下）

```objc
- (NSArray *)getStackBlock{
    int val = 10;
    return [NSArray arrayWithObjects:
    			^{NSLog(@"val = %d",val);},
    			^{NSLog(@"val = %d",val);} ,nil];
}

- (void)testStatckBloc{
    
    NSArray *array = [self getStackBlock];
    void(^blk)(void) = array.firstObject;
    blk();
}
```

2. Masonary 是否会造成循环引用？ 

``` objc
[self.headView mas_makeConstraints:^(MASConstraintMaker *make) {
    make.centerY.equalTo(self.otherView.mas_centerY);
}];
```










