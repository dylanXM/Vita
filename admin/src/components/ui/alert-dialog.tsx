import * as React from "react";
import { AlertDialog as AD } from "radix-ui";
import { cn } from "@/lib/utils";
import { buttonVariants } from "./button";

export const AlertDialog = AD.Root;
export const AlertDialogTrigger = AD.Trigger;

export const AlertDialogAction = React.forwardRef<
  React.ComponentRef<typeof AD.Action>,
  React.ComponentPropsWithoutRef<typeof AD.Action>
>(({ className, ...props }, ref) => (
  <AD.Action ref={ref} className={cn(buttonVariants(), className)} {...props} />
));
AlertDialogAction.displayName = "AlertDialogAction";

export const AlertDialogCancel = React.forwardRef<
  React.ComponentRef<typeof AD.Cancel>,
  React.ComponentPropsWithoutRef<typeof AD.Cancel>
>(({ className, ...props }, ref) => (
  <AD.Cancel ref={ref} className={cn(buttonVariants({ variant: "outline" }), className)} {...props} />
));
AlertDialogCancel.displayName = "AlertDialogCancel";

export const AlertDialogContent = React.forwardRef<
  React.ComponentRef<typeof AD.Content>,
  React.ComponentPropsWithoutRef<typeof AD.Content>
>(({ className, ...props }, ref) => (
  <AD.Portal>
    <AD.Overlay className="fixed inset-0 z-50 bg-black/60" />
    <AD.Content
      ref={ref}
      className={cn(
        "fixed left-1/2 top-1/2 z-50 grid w-full max-w-md -translate-x-1/2 -translate-y-1/2 gap-4 rounded-xl border bg-background p-6 shadow-lg",
        className,
      )}
      {...props}
    />
  </AD.Portal>
));
AlertDialogContent.displayName = "AlertDialogContent";

export function AlertDialogHeader({ className, ...props }: React.ComponentProps<"div">) {
  return <div className={cn("flex flex-col gap-1.5", className)} {...props} />;
}

export function AlertDialogFooter({ className, ...props }: React.ComponentProps<"div">) {
  return <div className={cn("flex flex-col-reverse gap-2 sm:flex-row sm:justify-end", className)} {...props} />;
}

export const AlertDialogTitle = React.forwardRef<
  React.ComponentRef<typeof AD.Title>,
  React.ComponentPropsWithoutRef<typeof AD.Title>
>(({ className, ...props }, ref) => (
  <AD.Title ref={ref} className={cn("text-lg font-semibold tracking-tight", className)} {...props} />
));
AlertDialogTitle.displayName = "AlertDialogTitle";

export const AlertDialogDescription = React.forwardRef<
  React.ComponentRef<typeof AD.Description>,
  React.ComponentPropsWithoutRef<typeof AD.Description>
>(({ className, ...props }, ref) => (
  <AD.Description ref={ref} className={cn("text-sm text-muted-foreground", className)} {...props} />
));
AlertDialogDescription.displayName = "AlertDialogDescription";
