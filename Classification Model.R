---
Title: "Athlete Classification Project"
Author: "Tej Rai"
---

library(readr)
library(ggplot2)
library(ggformula)
library(dplyr)
library(caret)
library(tidyverse)
library(FNN)
library(corrplot)
library(FNN)
library(randomForest)
library(pdp)
library(gridExtra)
library(pROC)
library(patchwork)


athletes <- read.csv("Athletes.csv")  


#Data Preparation
#Exploratory Data Analysis & Data Cleaning:

# EDA
summary(athletes)
str(athletes)

# Correlation matrix
cor_matrix <- cor(athletes %>% select_if(is.numeric))
corrplot::corrplot(cor_matrix, method = "circle")

# Convert categorical variables to factors
athletes <- athletes %>%
  mutate(Sport_group = as.factor(Sport_group),
         Sex = as.factor(Sex))

# Check skewness of numeric variables
numeric_vars <- athletes %>% select_if(is.numeric)
skewness <- apply(numeric_vars, 2, e1071::skewness)
print(skewness)


# Apply log transformation to reduce skewness
athletes <- athletes %>%
  mutate(Log_Ferr = log1p(Ferr),
         Log_SSF = log1p(SSF),
         Log_BMI = log1p(BMI),
         Log_Bfat = log1p(Bfat),
         Log_WCC = log1p(WCC))

# Drop the original columns that were transformed
athletes <- athletes %>% select(-Ferr, -SSF, -BMI, -Bfat, -WCC)

# Check skewness again after transformation
numeric_vars_transformed <- athletes %>% select_if(is.numeric)
skewness_transformed <- apply(numeric_vars_transformed, 2, e1071::skewness)
print(skewness_transformed)

head(athletes)
dim(athletes)

Fitting the Models:

# Splitting the data into training and testing sets using a 2/3 split
set.seed(123)
groups <- c(rep(1, 134), rep(2, 68))  # 134 for training (2/3 of 202), 68 for testing (1/3 of 202)
random_groups <- sample(groups, 202)
in_train <- (random_groups == 1)
head(in_train)

athletesTrain <- athletes[in_train, ]
athletesTest <- athletes[!in_train, ]

#KNN Model
#k tuning 

# Define train control for 10-fold cross-validation
train_control <- trainControl(method = "cv", number = 10)

# Define parameter grid for KNN
knn_grid <- expand.grid(k = seq(1, 30, by = 1))

# Train KNN model with 10-fold cross-validation
set.seed(123)
knn_model <- train(Sport_group ~ ., data = athletesTrain, method = "knn", 
                   trControl = train_control, tuneGrid = knn_grid)

# Extract accuracy results
accuracy_results <- knn_model$results

# Find the best k value
best_k <- accuracy_results %>%
  filter(Accuracy == max(Accuracy)) %>%
  select(k)

print(paste("Best k value: ", best_k$k))

# Plot accuracy vs k
ggplot(accuracy_results, aes(x = k, y = Accuracy)) +
  geom_line() +
  geom_point() +
  labs(title = "Accuracy vs k for KNN Model",
       x = "k value",
       y = "Accuracy") +
  theme_minimal()

# Train the final KNN model using the best k value on the entire training set
final_knn_model <- train(Sport_group ~ ., data = athletesTrain, method = "knn",
                         trControl = trainControl(method = "none"), tuneGrid = expand.grid(k = best_k))

# Evaluate the KNN model on the test set using the best k value
knn_predictions <- predict(final_knn_model, newdata = athletesTest)
knn_conf_matrix <- confusionMatrix(knn_predictions, athletesTest$Sport_group)
print(knn_conf_matrix)

#Random Forest
#mtry tuning

# Define the mtry values to test
mtry_values <- c(1, 2, 3, 4, 5, 12) #p = 12, sqrt(12) = 3.46  

# Define train control for 10-fold cross-validation
train_control <- trainControl(method = "cv", number = 10)

# Define parameter grid for Random Forest
rf_grid <- expand.grid(mtry = mtry_values)

# Train Random Forest model with 10-fold cross-validation
set.seed(123)
rf_model <- train(Sport_group ~ ., data = athletesTrain, method = "rf", 
                  trControl = train_control, tuneGrid = rf_grid)

# Extract accuracy results
accuracy_results <- rf_model$results

# Best mtry value
best_mtry <- accuracy_results %>%
  filter(Accuracy == max(Accuracy)) %>%
  select(mtry)

# Plot accuracy vs k
ggplot(accuracy_results, aes(x = mtry, y = Accuracy)) +
  geom_line() +
  geom_point() +
  labs(title = "Accuracy vs mtry for RF Model",
       x = "mtry value",
       y = "Accuracy") +
  theme_minimal()

best_mtry <- rf_model$bestTune$mtry
print(paste("Best mtry value: ", best_mtry))

# Evaluate the Random Forest model on the test set using the best mtry value
rf_predictions <- predict(rf_model, newdata = athletesTest)
rf_conf_matrix <- confusionMatrix(rf_predictions, athletesTest$Sport_group)
print(rf_conf_matrix)

#For loop to conduct an outer layer of 5-fold cross-validation (containing both of the modeling types):

# Set seed
set.seed(123)

# Create outer folds for 5-fold cross-validation
outer_folds <- createFolds(athletes$Sport_group, k = 5, list = TRUE)

# Initialize lists to store results
outer_results_knn <- list()
outer_results_rf <- list()

# Best hyperparameters from step 4
best_k <- 4  
best_mtry <- 2

# Outer loop over each fold
for (i in 1:5) {
  # Split the data
  train_data <- athletes[-outer_folds[[i]], ]
  test_data <- athletes[outer_folds[[i]], ]
  
  # KNN model with best k
  knn_model <- train(Sport_group ~ ., data = train_data, method = "knn", 
                     trControl = trainControl(method = "cv", number = 10), tuneGrid = expand.grid(k = best_k))
  knn_predictions <- predict(knn_model, newdata = test_data)
  knn_conf_matrix <- confusionMatrix(knn_predictions, test_data$Sport_group)
  knn_accuracy <- knn_conf_matrix$overall["Accuracy"]
  outer_results_knn[[i]] <- list(model = knn_model, confusion_matrix = knn_conf_matrix, accuracy = knn_accuracy)
  
  # Random Forest model with best mtry
  rf_model <- train(Sport_group ~ ., data = train_data, method = "rf", 
                    trControl = trainControl(method = "cv", number = 10), tuneGrid = expand.grid(mtry = best_mtry))
  rf_predictions <- predict(rf_model, newdata = test_data)
  rf_conf_matrix <- confusionMatrix(rf_predictions, test_data$Sport_group)
  rf_accuracy <- rf_conf_matrix$overall["Accuracy"]
  outer_results_rf[[i]] <- list(model = rf_model, confusion_matrix = rf_conf_matrix, accuracy = rf_accuracy)
}

# Find the best fold for KNN
best_knn_fold <- which.max(sapply(outer_results_knn, function(x) x$accuracy))
print(paste("Best Fold for KNN - Fold", best_knn_fold))
print(outer_results_knn[[best_knn_fold]]$confusion_matrix)

# Find the best fold for Random Forest
best_rf_fold <- which.max(sapply(outer_results_rf, function(x) x$accuracy))
print(paste("Best Fold for Random Forest - Fold", best_rf_fold))
print(outer_results_rf[[best_rf_fold]]$confusion_matrix)

# Extract cross-validation results
knn_results <- knn_model$resample
rf_results <- rf_model$resample

# Combine results into a single data frame
results <- bind_rows(
  knn_results %>% mutate(Model = "KNN"),
  rf_results %>% mutate(Model = "Random Forest")
)

# Plot the accuracies
ggplot(results, aes(x = Model, y = Accuracy, fill = Model)) +
  geom_boxplot() +
  labs(title = "Comparison of KNN and Random Forest Accuracies", x = "Model", y = "Accuracy") +
  theme_minimal()

#Fit "best" model on the entire data set:

set.seed(123)

train_control <- trainControl(method = "cv", number = 10)

best_mtry <- 2

# Fit the final Random Forest model using the best mtry value on the entire dataset
final_rf_model <- train(Sport_group ~ ., data = athletes, method = "rf",
                        trControl = train_control, tuneGrid = expand.grid(mtry = best_mtry))

# Print the final model
print(final_rf_model)


# Get variable importance
var_imp <- varImp(final_rf_model)
print(var_imp)

# Plot variable importance
varImpPlot(final_rf_model$finalModel, n.var = 10, main = "Variable Importance Plot")


#Partial Dependence Plots

par.Log_SSF <- partial(final_rf_model, pred.var = c("Log_SSF"), chull = TRUE)
plot.Log_SSF <- autoplot(par.Log_SSF, contour = TRUE)

par.Log_Bfat  <- partial(final_rf_model, pred.var = c("Log_Bfat"), chull = TRUE)
plot.Log_Bfat  <- autoplot(par.Log_Bfat , contour = TRUE)

par.Hg  <- partial(final_rf_model, pred.var = c("Hg"), chull = TRUE)
plot.Hg  <- autoplot(par.Hg , contour = TRUE)

grid.arrange(plot.Log_SSF, plot.Log_Bfat, plot.Hg)

# Violin plot for Log_SSF
violin_log_ssf <- ggplot(athletes, aes(x = Sport_group, y = Log_SSF, fill = Sport_group)) +
  geom_violin() +
  geom_boxplot(width = 0.2, fill = "white", outlier.shape = NA) +
  ylim(3.5, 5.75) +  
  labs(title = "Violin Plot of Log_SSF by Sport Group", x = "Sport Group", y = "Log_SSF") +
  theme_minimal()

# Violin plot for Log_Bfat
violin_log_bfat <- ggplot(athletes, aes(x = Sport_group, y = Log_Bfat, fill = Sport_group)) +
  geom_violin() +
  geom_boxplot(width = 0.2, fill = "white", outlier.shape = NA) +
  ylim(1.5, 4) +  
  labs(title = "Violin Plot of Log_Bfat by Sport Group", x = "Sport Group", y = "Log_Bfat") +
  theme_minimal()

# Violin plot for Hg
violin_Hg <- ggplot(athletes, aes(x = Sport_group, y = Hg, fill = Sport_group)) +
  geom_violin() +
  geom_boxplot(width = 0.2, fill = "white", outlier.shape = NA) +
  labs(title = "Violin Plot of Hg by Sport Group", x = "Sport Group", y = "Hg") +
  theme_minimal()

grid.arrange(violin_log_ssf, violin_log_bfat, violin_Hg, ncol = 1)

#Joint Effect of Log_SSF & Hg



# Calculate the mode for the Sex variable
mode_sex <- athletes %>%
  group_by(Sex) %>%
  summarise(count = n()) %>%
  arrange(desc(count)) %>%
  slice(1) %>%
  pull(Sex)

# Create example data with median values for other predictors and mode for Sex
example_data <- athletes %>%
  mutate(across(c(-Sex, -Log_SSF, -Hg, -Sport_group), median)) %>%
  mutate(Sex = mode_sex)

example_data <- example_data %>%
  mutate(pred_Sport_group = predict(final_rf_model, example_data, type = "prob")[,1])

plots <- list()

for (i in seq_along(sport_groups)) {
  example_data <- example_data %>%
    mutate(pred_Sport_group = predictions[, i])
  
  plot <- example_data %>%
    gf_point(pred_Sport_group ~ Log_SSF, color =~ Hg) %>%
    gf_refine(scale_color_gradient(low = "darkblue", high = "red")) +
    labs(title = paste("Predicted Probability for", sport_groups[i]),
         x = "Log_SSF", y = "Predicted Probability")
  
  plots[[i]] <- plot
}

grid.arrange(grobs = plots, ncol = 1)


