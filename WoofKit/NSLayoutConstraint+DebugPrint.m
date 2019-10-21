//
//  NSLayoutConstraint+DebugPrint.m
//  houzz
//
//  Created by Guy Shaviv on 17/4/2014.
//
//

#import "NSLayoutConstraint+DebugPrint.h"
@import ObjectiveC;

NSString * ClassName(Class c) {
    return [[NSStringFromClass(c) componentsSeparatedByString:@"."] lastObject];
}

static NSString * isClassPropertyOf(Class parentClass, id child, id parent) {
    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList(parentClass, &count);

    @try {
        for (int i = 0; i < count; ++i) {
            objc_property_t property = properties[i];
            const char *name = property_getName(property);
            const char *attributes = property_getAttributes(property);
            char type = attributes[1];

            if (type != '@') continue;

            char *getter = strstr(attributes, ",G");
            char *toFree = NULL;

            if (getter) {
                getter = strdup(getter + 2);
                toFree = getter;
                getter = strsep(&getter, ",");
            } else {
                toFree = strdup(name);
            }

            SEL getterSel = sel_registerName(getter);
            free(toFree);

            if (getterSel == nil) {
                continue;
            }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

            if ([parent respondsToSelector:getterSel] && ![NSStringFromSelector(getterSel) isEqualToString:@"hzBarLayoutGuide"]) {
                id value = [parent performSelector:getterSel withObject:nil];
#pragma clang diagnostic pop

                if (value == child) {
                    free(properties);
                    return [NSString stringWithCString:name encoding:NSASCIIStringEncoding];
                }
            }
        }

        free(properties);

        if (class_getSuperclass(parentClass)) {
            Class superclass = class_getSuperclass(parentClass);
            NSString *nameOfClass = ClassName(superclass);

            if ((![nameOfClass hasPrefix:@"UI"] && ![nameOfClass hasPrefix:@"NS"]) || [nameOfClass isEqualToString:@"UIViewController"]) {
                return isClassPropertyOf(superclass, child, parent);
            }
        }

        return nil;
    } @catch (id e) {
        if (properties != nil && properties != NULL) {
            free(properties);
        }

        return nil;
    }
}

NSString * isPropertyOf(id parent, id child) {
    if (!parent) return nil;

    Class parentClass = [parent class];

    return isClassPropertyOf(parentClass, child, parent);
}

@implementation NSLayoutConstraint (DebugPrint)

- (NSString *) attributeString:(NSLayoutAttribute)attribute {
    NSString *attr = nil;

    switch (attribute) {
        case NSLayoutAttributeLeft:
            attr = @"left";
            break;

        case NSLayoutAttributeRight:
            attr = @"right";
            break;

        case NSLayoutAttributeTop:
            attr = @"top";
            break;

        case NSLayoutAttributeBottom:
            attr = @"bottom";
            break;

        case NSLayoutAttributeLeading:
            attr = @"leading";
            break;

        case NSLayoutAttributeTrailing:
            attr = @"trailing";
            break;

        case NSLayoutAttributeWidth:
            attr = @"width";
            break;

        case NSLayoutAttributeHeight:
            attr = @"height";
            break;

        case NSLayoutAttributeCenterX:
            attr = @"centerX";
            break;

        case NSLayoutAttributeCenterY:
            attr = @"centerY";
            break;

        case NSLayoutAttributeBaseline:
            attr = @"baseline";
            break;

        case NSLayoutAttributeLeftMargin:
            attr = @"leftMargin";
            break;

        case NSLayoutAttributeRightMargin:
            attr = @"rightMargin";
            break;

        case NSLayoutAttributeLeadingMargin:
            attr = @"leadingMargin";
            break;

        case NSLayoutAttributeTrailingMargin:
            attr = @"trailingMargin";
            break;

        default:
            attr = [@(attribute)stringValue];
            break;
    }
    return attr;
}

+ (NSString *) descriptionForObject:(id)obj {
    @try {
        NSString *objClassString = ClassName([obj class]);
        BOOL isSystemObjectClass = [[objClassString substringToIndex:1] isEqualToString:@"_"];
        BOOL skip = [objClassString isEqualToString:@"_UIOLAGapGuide"];

        if (isSystemObjectClass && !skip) {
            if ([obj respondsToSelector:@selector(description)]) {
                return [obj description];
            } else if ([obj isKindOfClass:NSObject.class]) {
                return NSStringFromClass([(NSObject *)obj class]);
            }
        }

        if ([obj isKindOfClass:[UIView class]]) {
            UIView *v = obj;
            NSString *name;
//            NSString *name = isPropertyOf(v.viewController, v);
//
//            if (name) return [NSString stringWithFormat:@"%@.%@", ClassName([v.viewController class]), name];

            name = isPropertyOf(v.superview, v);

            if (name) return [NSString stringWithFormat:@"%@.%@", ClassName([v.superview class]), name];

            if ([v.superview respondsToSelector:@selector(reuseIdentifier)] && [(id)v.superview reuseIdentifier]) {
                return [NSString stringWithFormat:@"'%@'", [[(id)v.superview reuseIdentifier] stringByReplacingOccurrencesOfString:@" " withString:@"_"]];
            }

            for (UIView *test = v.superview.superview; test; test = test.superview) {
                name = isPropertyOf(test, v);

                if (name) return [NSString stringWithFormat:@"%@.%@", ClassName([v.superview class]), name];
            }

            /* if (v.stringTag) {
                return v.stringTag;
            } else*/ if (v.tag > 0) {
                return [NSString stringWithFormat:@"[%@ tag=%ld]", ClassName(v.class), (long)v.tag];
            }
        } else if ([obj isKindOfClass:[UILayoutGuide class]]) {
            UILayoutGuide *o = obj;

            if (o.identifier) {
                return [NSString stringWithFormat:@"[%@:%@:%8p]", NSStringFromClass(o.class), o.identifier, o];
            } else {
                return o.description;
            }
        }

        if ([obj isKindOfClass:[UILabel class]]) {
            return [NSString stringWithFormat:@"%@:'%@'", ClassName([obj class]), [(UILabel *)obj text]];
        }

        if ([obj respondsToSelector:@selector(accessibilityLabel)] && [(id)obj accessibilityLabel]) {
            return [[obj accessibilityIdentifier] stringByReplacingOccurrencesOfString:@" " withString:@"_"];
        }

        if ([obj respondsToSelector:@selector(accessibilityIdentifier)] && [(id)obj accessibilityIdentifier]) {
            return [[obj accessibilityIdentifier] stringByReplacingOccurrencesOfString:@" " withString:@"_"];
        }
    } @catch (id e) {
    }

    return [NSString stringWithFormat:@"[%@:%p]", ClassName([obj class]), obj];
}

- (NSString *) layoutRelationshipDescription {
    switch (self.relation) {
        case NSLayoutRelationLessThanOrEqual:
            return @"<=";

        case NSLayoutRelationEqual:
            return @"==";

        case NSLayoutRelationGreaterThanOrEqual:
            return @">=";

        default:
            break;
    }
    return @"?";
}

#ifdef DEBUG
- (NSString *) description {
    NSMutableString *desc = [NSMutableString stringWithFormat:@"<%@:%p %@.%@ %@", ClassName([self class]), self, [NSLayoutConstraint descriptionForObject:self.firstItem], [self attributeString:self.firstAttribute], [self layoutRelationshipDescription]];

    if (self.secondItem) {
        [desc appendFormat:@" %@.%@", [NSLayoutConstraint descriptionForObject:self.secondItem], [self attributeString:self.secondAttribute]];

        if (fabs(self.multiplier) > 1e-6) {
            if (fabs(self.multiplier - 1.) > 1e-6) {
                if (fabs(self.multiplier) > 1) {
                    [desc appendFormat:@" * %g", self.multiplier];
                } else {
                    [desc appendFormat:@" / %g", 1. / self.multiplier];
                }
            }
        }
    }

    if (fabs(self.constant) > .01) {
        if (self.secondItem) {
            if (self.constant > 0) {
                [desc appendString:@" +"];
            } else {
                [desc appendString:@" -"];
            }
        }

        [desc appendFormat:@" %g", fabs(self.constant)];
    } else if (!self.secondItem) {
        [desc appendString:@" 0"];
    }

    if (self.priority < UILayoutPriorityRequired) {
        [desc appendFormat:@" @ %.0f", self.priority];
    }

    [desc appendString:@">"];
    return desc;
}

#endif /* ifdef DEBUG */
@end
