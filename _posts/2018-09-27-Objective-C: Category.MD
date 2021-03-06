# Category 使用介绍
Category翻译为分类，是Objective-C 2.0 的时候提供的新的特性，可以动态地为已有的类添加新的行为。增加扩展性，目前一般暴露类的私有方法，复写父类的方法，和新增方法。

## category的实现
通过查看OC的类和对象，在runtime的时候都是struct表示的，category 在runtime层用结构体`category_t`，在`objc-runtime-new.h`中查看`category_t`的结构。

```
struct category_t {
    const char *name; // 类的名字
    classref_t cls; // 类 cls 
    struct method_list_t *instanceMethods; // 给类添加的实例方法
    struct method_list_t *classMethods; //  给类添加的类方法
    struct protocol_list_t *protocols; // 给类实现的协议列表
    struct property_list_t *instanceProperties; // 给类添加的所有属性
    // Fields below this point are not always present on disk.
    struct property_list_t *_classProperties; // 给类添加的属性

    method_list_t *methodsForMeta(bool isMeta) {
        if (isMeta) return classMethods;
        else return instanceMethods;
    }

    property_list_t *propertiesForMeta(bool isMeta, struct header_info *hi);
};

```
可以看出，category为当前的类添加了 类的实例方法，类的协议，类的属性。

**Category 能否添加属性？** 在面试的时候，经常会遇到这个问题?

对于这个问题，都是回答说，不能添加类的属性的，其实类的属性是可以添加的，但是由于 对象的占用的内存大小是固定的， 如果动态的改变会造成很大的问题，所以通过`Category`添加的属性不会自动生成成员变量，因此对象的get 和 set 是不会自动生成的。 需要我们自己手动去创建get 和 set 方法。 可以知道 `property` 是相当于 实例变量 + 存取器（`getter` && `setter`），没有实例变量，所以 Getter 和 Setter 就不能直接用 `_xxx = A; ` 和 `return _xxx;` 这种来实现。需要使用`Association `。 

```
xxx (category).h

@property (nonatomic, copy) NSString *name;

xxx (category).m

#import <objc/runtime.h>


- (NSString *)name{
    return objc_getAssociatedObject(self,@"associatedNameKey");
}

- (void)setName:(NSString *)name{
    objc_setAssociatedObject(self, @"associatedNameKey", name, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

```
### Association的原理
`Association` 会额外创建一个哈希表（`AssociationsHashMap`）， 在hash表中存储着 对象地址为Key（self的地址） 一个`AssociationMap`(C++) 为value 

AssociationMap 中存储着真正的 设置的Key 和 Value。 value 为`ObjcAssociation`。

ObjcAssociation 结构体 `_policy` 表示关联策略，`_value` 表示关联对象。

#### Association中添加的对象什么时候释放？

Association中的对象释放其实是跟[weak对象是在什么时候被设置nil的周期是一样的](http://jellygd.github.io/2018/09/26/Memory-weak%E5%AE%9E%E7%8E%B0%E8%BF%87%E7%A8%8B/)。

下面这个是对象在`dealloc` 的时候做了什么操作。

```
1、object在release的时候 引用计数器减1，当达到0 的时候，对象释放。
2、调用 当前对象的dealloc，然后调用父类的Dealloc，直到调用NSObject的dealloc方法。
3、NSObject的dealloc 会调用 objc_rootDealloc方法。
4、objc_rootDealloc => objc_despose() 然后调用 objc_desposeInstance();
5、然后调用objc_clear_deallocating();
6、调用objc_storeWeak(&objc1); 将weak弱引用对象变成nil。
```
对于Association会在objc_desposeInstance()的时候增加一个处理。

```
// 判断是否有通过runtime 的Association 添加新的属性。
if( obj->hasAssociatedObjects()){
    // 如果是TaggedPointer优化，那这个方法也会返回true
    调用_object_remove_assocations(obj)
}
```

### 查看Category的实现


通过`clang -rewrite-objc MyClass.m` 来查看Category后的变化

```
#import "MyClass.h"

@implementation MyClass

- (void)printName
{
    NSLog(@"%@",@"MyClass");
}

@end


@implementation MyClass(MyCategory)

- (void)printName
{
    NSLog(@"%@",@"MyCategory");
}

@end

```
clang 后的代码有很多有3.5M， 9w多行差不多10w行。查找到 `Myclass`的代码如下：（经过简化，简化了 方法列表，元类，类的结构，属性列表）

```

static struct /*_method_list_t*/ {
	unsigned int entsize;  // sizeof(struct _objc_method)
	unsigned int method_count;
	struct _objc_method method_list[1];
} _OBJC_$_CATEGORY_INSTANCE_METHODS_MyClass_$_MyCategory __attribute__ ((used, section ("__DATA,__objc_const"))) = {
	sizeof(_objc_method),
	1,
	{{(struct objc_selector *)"printName", "v16@0:8", (void *)_I_MyClass_MyCategory_printName}}
};


static struct _category_t _OBJC_$_CATEGORY_MyClass_$_MyCategory __attribute__ ((used, section ("__DATA,__objc_const"))) = 
{
	"MyClass",
	0, // &OBJC_CLASS_$_MyClass,
	(const struct _method_list_t *)&_OBJC_$_CATEGORY_INSTANCE_METHODS_MyClass_$_MyCategory,
	0,
	0,
	(const struct _prop_list_t *)&_OBJC_$_PROP_LIST_MyClass_$_MyCategory,
};
static void OBJC_CATEGORY_SETUP_$_MyClass_$_MyCategory(void ) {
	_OBJC_$_CATEGORY_MyClass_$_MyCategory.cls = &OBJC_CLASS_$_MyClass;
}
#pragma section(".objc_inithooks$B", long, read, write)
__declspec(allocate(".objc_inithooks$B")) static void *OBJC_CATEGORY_SETUP[] = {
	(void *)&OBJC_CATEGORY_SETUP_$_MyClass_$_MyCategory,
};
static struct _class_t *L_OBJC_LABEL_CLASS_$ [1] __attribute__((used, section ("__DATA, __objc_classlist,regular,no_dead_strip")))= {
	&OBJC_CLASS_$_MyClass,
};
static struct _category_t *L_OBJC_LABEL_CATEGORY_$ [1] __attribute__((used, section ("__DATA, __objc_catlist,regular,no_dead_strip")))= {
	&_OBJC_$_CATEGORY_MyClass_$_MyCategory,
};
```

在clang之后，可以看出，编译器生成了 `_CATEGORY_INSTANCE_METHODS_MyClass_$_MyCategory`和属性列表`_OBJC_$_PROP_LIST_MyClass_$_MyCategory`。 可以看出都是static， 所以名字是不能重复的不然会出错。

```
__declspec(allocate(".objc_inithooks$B")) static void *OBJC_CATEGORY_SETUP[] = {
	(void *)&OBJC_CATEGORY_SETUP_$_MyClass_$_MyCategory,
};

```
用于初始化Category。

```
static struct _category_t *L_OBJC_LABEL_CATEGORY_$ [1] __attribute__((used, section ("__DATA, __objc_catlist,regular,no_dead_strip")))= {
	&_OBJC_$_CATEGORY_MyClass_$_MyCategory,
};
```
生成了一个category_t 数组来保存当前类的所有分类。如果有多个会生成对应长度的一个数组，用于运行期Category的加载。

## category是如何覆盖父类方法？
Objective-C的运行是依赖OC的runtime的，而OC的runtime是通过dyld动态加载的。
通过查看`objc_init `方法，查看category的加载过程。

```
/***********************************************************************
* _objc_init
* Bootstrap initialization. Registers our image notifier with dyld.
* Called by libSystem BEFORE library initialization time
**********************************************************************/

void _objc_init(void)
{
    static bool initialized = false;
    if (initialized) return;
    initialized = true;
    
    // fixme defer initialization until an objc-using image is found?
    environ_init();
    tls_init();
    static_init();
    lock_init();
    exception_init();

    _dyld_objc_notify_register(&map_images, load_images, unmap_image);
}

```

category 是通map_images 把方法添加到类中的。

```
/***********************************************************************
* map_images
* Process the given images which are being mapped in by dyld.
* Calls ABI-agnostic code after taking ABI-specific locks.
*
* Locking: write-locks runtimeLock
**********************************************************************/
void
map_images(unsigned count, const char * const paths[],
           const struct mach_header * const mhdrs[])
{
    rwlock_writer_t lock(runtimeLock);
    return map_images_nolock(count, paths, mhdrs);
}
```
`map_images` 会对runtimeLock加锁，然后调用 `map_images_nolock `,里面代码比较多，就直接拿关键的代码来查看。


```
void 
map_images_nolock(unsigned mhCount, const char * const mhPaths[],
                  const struct mach_header * const mhdrs[])
{
	if (hCount > 0) {
        _read_images(hList, hCount, totalClasses, unoptimizedTotalClasses);
    }

    firstTime = NO;
}
```

```
// Discover categories. 
    for (EACH_HEADER) {
        category_t **catlist = 
            _getObjc2CategoryList(hi, &count);
        bool hasClassProperties = hi->info()->hasCategoryClassProperties();

        for (i = 0; i < count; i++) {
            category_t *cat = catlist[i];
            Class cls = remapClass(cat->cls);

            if (!cls) {
                // Category's target class is missing (probably weak-linked).
                // Disavow any knowledge of this category.
                catlist[i] = nil;
                if (PrintConnecting) {
                    _objc_inform("CLASS: IGNORING category \?\?\?(%s) %p with "
                                 "missing weak-linked target class", 
                                 cat->name, cat);
                }
                continue;
            }

            // Process this category. 
            // First, register the category with its target class. 
            // Then, rebuild the class's method lists (etc) if 
            // the class is realized. 
            bool classExists = NO;
            if (cat->instanceMethods ||  cat->protocols  
                ||  cat->instanceProperties) 
            {
                addUnattachedCategoryForClass(cat, cls, hi);
                if (cls->isRealized()) {
                    remethodizeClass(cls);
                    classExists = YES;
                }
                if (PrintConnecting) {
                    _objc_inform("CLASS: found category -%s(%s) %s", 
                                 cls->nameForLogging(), cat->name, 
                                 classExists ? "on existing class" : "");
                }
            }

            if (cat->classMethods  ||  cat->protocols  
                ||  (hasClassProperties && cat->_classProperties)) 
            {
                addUnattachedCategoryForClass(cat, cls->ISA(), hi);
                if (cls->ISA()->isRealized()) {
                    remethodizeClass(cls->ISA());
                }
                if (PrintConnecting) {
                    _objc_inform("CLASS: found category +%s(%s)", 
                                 cls->nameForLogging(), cat->name);
                }
            }
        }
    }
```

1)、把category的实例方法、协议以及属性添加到类上
2)、把category的类方法和协议添加到类的metaclass上
3)、把category的属性添加到类的metaclass上


`addUnattachedCategoryForClass`只是把类和category做一个关联映射，`remethodizeClass `是真正处理把Category添加到类中操作。

```
/***********************************************************************
* remethodizeClass
* Attach outstanding categories to an existing class.
* Fixes up cls's method list, protocol list, and property list.
* Updates method caches for cls and its subclasses.
* Locking: runtimeLock must be held by the caller
**********************************************************************/
static void remethodizeClass(Class cls)
{
    category_list *cats;
    bool isMeta;

    runtimeLock.assertWriting();

    isMeta = cls->isMetaClass();

    // Re-methodizing: check for more categories
    if ((cats = unattachedCategoriesForClass(cls, false/*not realizing*/))) {
        if (PrintConnecting) {
            _objc_inform("CLASS: attaching categories to class '%s' %s", 
                         cls->nameForLogging(), isMeta ? "(meta)" : "");
        }
        
        attachCategories(cls, cats, true /*flush caches*/);        
        free(cats);
    }
}
```

看代码的话，真正的调用方法是`attachCategories `

```
// Attach method lists and properties and protocols from categories to a class.
// Assumes the categories in cats are all loaded and sorted by load order, 
// oldest categories first.
static void 
attachCategories(Class cls, category_list *cats, bool flush_caches)
{
    if (!cats) return;
    if (PrintReplacedMethods) printReplacements(cls, cats);

    bool isMeta = cls->isMetaClass();

    // fixme rearrange to remove these intermediate allocations
    method_list_t **mlists = (method_list_t **)
        malloc(cats->count * sizeof(*mlists));
    property_list_t **proplists = (property_list_t **)
        malloc(cats->count * sizeof(*proplists));
    protocol_list_t **protolists = (protocol_list_t **)
        malloc(cats->count * sizeof(*protolists));

    // Count backwards through cats to get newest categories first
    int mcount = 0;
    int propcount = 0;
    int protocount = 0;
    int i = cats->count;
    bool fromBundle = NO;
    while (i--) { //注意这里， 是倒序加入的。
        auto& entry = cats->list[i];

        method_list_t *mlist = entry.cat->methodsForMeta(isMeta);
        if (mlist) {
            mlists[mcount++] = mlist;
            fromBundle |= entry.hi->isBundle();
        }

        property_list_t *proplist = 
            entry.cat->propertiesForMeta(isMeta, entry.hi);
        if (proplist) {
            proplists[propcount++] = proplist;
        }

        protocol_list_t *protolist = entry.cat->protocols;
        if (protolist) {
            protolists[protocount++] = protolist;
        }
    }

    auto rw = cls->data();

    prepareMethodLists(cls, mlists, mcount, NO, fromBundle);
    rw->methods.attachLists(mlists, mcount);
    free(mlists);
    if (flush_caches  &&  mcount > 0) flushCaches(cls);

    rw->properties.attachLists(proplists, propcount);
    free(proplists);

    rw->protocols.attachLists(protolists, protocount);
    free(protolists);
}

```

这里通过获取到当前了的所有分类，然后倒序的获取每个分类中相对应的方法，把所有的方法都添加到`method_list_t`结构体的mlists中， 也就是最后加入的Category的方法在前面。proplists 和 protolists都是相同的处理。内部调用`fixupMethodList` 对方法进行插入排序 里面调用`std::stable_sort` 

**注意**

1)、category的方法没有“完全替换掉”原来类已经有的方法，也就是说如果category和原来类都有methodA，那么category附加完成之后，类的方法列表里会有两个methodA

2)、category的方法被放到了新方法列表的前面，而原来类的方法被放到了新方法列表的后面，这也就是我们平常所说的category的方法会“覆盖”掉原来类的同名方法，这是因为运行时在查找方法的时候是顺着方法列表的顺序查找的，它只要一找到对应名字的方法，就会罢休^_^，殊不知后面可能还有一样名字的方法。





## 扩展阅读
### category和extension区别

#### 什么是extension？

extension被开发者称之为扩展、延展、匿名分类。extension看起来很像一个匿名的category，但是extension和category几乎完全是两个东西。

```
// 一般来说寄生于一个类的.m文件中。  也可以单独一个.h文件中。
@interface ViewController ()
 
@end

```


#### 使用区别
	extension可以添加实例变量，而category是无法添加实例变量。
	
	extension添加的方法 需要实现。  category添加的方法 可以不实现。
	
	extension和category都可以添加属性，但是category的属性不能生成成员变量和getter、setter方法的实现。

#### 代码时机
	extension在编译期决定，类的一部分。 而Category是在运行期决定的。 
	
	extension在编译期和头文件里的@interface以及实现文件里的@implement一起形成一个完整的类，它、extension伴随类的产生而产生，亦随之一起消亡。

#### 作用
	extension 一般作用定义私有属性 和私有方法。 隐藏类的私有信息。


### runtime是如何动态的创建类?
runtime的创建一个新的类，主要用的是 

```
Class newClass =  objc_allocateClassPair(<#Class  _Nullable __unsafe_unretained superclass#>, <#const char * _Nonnull name#>, <#size_t extraBytes#>)

class_addIvar(<#Class  _Nullable __unsafe_unretained cls#>, <#const char * _Nonnull name#>, <#size_t size#>, <#uint8_t alignment#>, <#const char * _Nullable types#>)

class_addMethod(<#Class  _Nullable __unsafe_unretained cls#>, <#SEL  _Nonnull name#>, <#IMP  _Nonnull imp#>, <#const char * _Nullable types#>)

class_addProtocol(<#Class  _Nullable __unsafe_unretained cls#>, <#Protocol * _Nonnull protocol#>)

class_addProperty(<#Class  _Nullable __unsafe_unretained cls#>, <#const char * _Nonnull name#>, <#const objc_property_attribute_t * _Nullable attributes#>, <#unsigned int attributeCount#>)

objc_registerClassPair(newClass)
```   

 动态创建 GDRuntime类 继承NSObject。 
 `objc_allocateClassPair `跟`objc_registerClassPair ` 需要配套使用。对类的增加方法，和变量 都要放在**Pair** 里面。  如下所示： 

``` 
/*
        如何添加类方法。
     */
 	Class newClass = objc_allocateClassPair([NSObject class], "GDRuntime", 0); // 为新创建的类分配内存， 参数1：新创建类的父类 参数2：新创建类的名称， 参数3：创建的内存空间大小 默认都写0。
    
    if (!class_addMethod(object_getClass(newClass), @selector(report1), (IMP)ReportFunction1, "v@:")){
        NSLog(@"add meta method reportFunction failed");
    }
    
    if (!class_addMethod(newClass, @selector(report), (IMP)ReportFunction, "v@:")) {
        NSLog(@"add method reportFunction failed");
    }
    
    if (!class_addIvar(newClass, "_name", sizeof(NSString *), log2(sizeof(NSString *)), @encode(NSString *))){
        NSLog(@"add ivar _name failed");
    }
    objc_registerClassPair(newClass);// 将新建的类注册到运行时系统，否则系统无法识别新建的类。
    // ** 注意点。
    if (!class_addIvar(newClass, "_name1", sizeof(NSString *), log2(sizeof(NSString *)), @encode(NSString *))){
        NSLog(@"add ivar _name1 failed");
    }
``` 

**注意** 
`_name1 `添加到`GDRuntime `是失败的。

`v@: ` 这个是代表传入的方法参数类型。

### load 和 initialize 的区别

#### 相同点
load 和 initialize 都是会只调用一次。 在类初始化之前会被调用。

#### 不同点
调用的时机不一样， load 是在main()函数之前调用， 而initialize 是在当前类被第一次使用的时候会被调用。
load方法的调用，是在Image.load 的时候，对所有的类进行所有的类的load方法.

#### 使用场景
load 方法一般使用场景是，例如swizzling(交换方法),Router的注册。
initialize 一般使用场景就是在类调用之前，初始化一些静态数据。

### 消息发送是如何找到IMP的？ 
消息发送，是Objective-C的一个特性， 一般来说，其他语言说的都是函数的调用，而在OC中说的是消息发送。 消息发送的机制主要依赖于运行时，在运行到的时候才决定被调用方和调用的函数。 主要有几个概念 methodLists (方法列表)，IMP（方法的实现地址，内存地址），SEL `@selector()`(方法选择器)，实例方法（需要对类初始化之后），类方法 （直接调用类中的方法 `+(void)xxx;` 以 + 好开头的方法）,isa (元类)。 这里不详细展开 有需要的自己去相对应的了解。

```
[self doxxx];

// 相当于

objc_msgSend(self,@selector(doxxx));

```

查找IMP的过程分为 **消息发送** 和 **消息转发**。

消息发送的过程

	1.在class 方法缓存 caches中查找是否有对应该的方法缓存，有则直接调用
	2.通过获取方法列表（区分类方法和实例方法）然后匹配方法 SEL 是否有对应的方法。
	3.如果当前类中没有找到，则继续会向父类查找，知道查找到根类 NSObject 或者 NSProxy中。
	4.找到相对应的方法，得到一个地址，则是IMP的地址。
	5.缓存到caches中，SEL为key，IMP为Value。 以便下次调用的时候能够快捷的调用。
	6.调用IMP。 

这个就是消息的发送过程， 需要区分是类方法列表 还是 实例方法列表， 因为方法的列表存储的位置是不一样的。  类方法列表存储在 obj_class中， 而实例方法列表存在isa(元类)中, 这个跟类的结构有关系。 

消息发送的过程，是比较简单，就是通过方法选择器，去查找方法的实现地址。 如果在消息发送过程中，没有找到方法的实现地址，则会进入到消息的转发。

消息的转发过程

	1. - (id)forwardingTargetForSelector:(SEL)aSelector 对当前类或者父类中不支持的方法编号，进行方法转换 也支持类方法的消息重定向 + (id)forwardingTargetForSelector:(SEL)aSelector
	2. - (NSInvocation *)methodSignatureForSelector：取到返回的方法签名用于生成NSInvocation对象，为接下来的完整的消息转发生成一个 NSMethodSignature对象
	3. - (void)forWardInvocation:(NSinvocation *)a //在程序崩溃之前，系统会做一次完整的消息转发。
        如果本类不能处理，则会调用超类的同名方法，在继承体系中每个类都有机会处理该方法调用的请求，一直到NSObject根类。
	4.找到消息的接受者之后，也就是真正找到方法的实现地址之后，缓存到caches中，再重新调用消息的发送过程。
	5.如果消息转发都没有找到当前的方法的IMP的时候，就会抛出异常（doesNotRecognizeSelector）。


## 面试题

```

NSObject+Sark.h


@interface NSObject (Sark)


+ (void)foo;

- (void)foo;

@end


NSObject+Sark.m

#import "NSObject+Sark.h"

@implementation NSObject (Sark)

- (void)foo{
    NSLog(@"IMP: -[NSObject(Sark) foo]");
}

@end


```
根据上面代码 
// 调用 
[NSObject foo]; 

会闪退吗？ 为什么？

